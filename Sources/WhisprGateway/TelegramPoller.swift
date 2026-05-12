import Foundation

private struct TelegramResponse: Decodable {
    let ok: Bool
    let result: [Update]
}

private struct Update: Decodable {
    let updateID: Int
    let message: TGMessage?
    enum CodingKeys: String, CodingKey {
        case updateID = "update_id"
        case message
    }
}

private struct TGMessage: Decodable {
    let chat: TGChat
    let text: String?
}

private struct TGChat: Decodable {
    let id: Int
}

final class TelegramPoller: Sendable {
    private let botToken: String
    private let chatID: Int
    // Only accessed from within the polling Task — no real concurrency hazard.
    private nonisolated(unsafe) var pollingTask: Task<Void, Never>?
    private nonisolated(unsafe) var offset: Int = 0

    private let onMessage: @Sendable @MainActor (String) -> Void
    private let onStatusChange: @Sendable @MainActor (String) -> Void

    init(
        botToken: String,
        chatID: Int,
        onMessage: @escaping @Sendable @MainActor (String) -> Void,
        onStatusChange: @escaping @Sendable @MainActor (String) -> Void
    ) {
        self.botToken = botToken
        self.chatID = chatID
        self.onMessage = onMessage
        self.onStatusChange = onStatusChange
    }

    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task {
            await skipOldMessages()
            await pollLoop()
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    // Uses timeout=0 to avoid a 30s wait on activation; advances offset past all existing messages.
    private func skipOldMessages() async {
        let updates = await fetchUpdates(offset: -1, timeout: 0) ?? []
        offset = updates.last.map { $0.updateID + 1 } ?? 0
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            guard let updates = await fetchUpdates(offset: offset, timeout: 30) else {
                await notifyStatus("Connection error — retrying...")
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                continue
            }
            for update in updates {
                if update.updateID >= offset { offset = update.updateID + 1 }
                guard let msg = update.message,
                      msg.chat.id == chatID,
                      let text = msg.text, !text.isEmpty else { continue }
                await notifyMessage(text)
            }
        }
    }

    private func fetchUpdates(offset: Int, timeout: Int) async -> [Update]? {
        var comps = URLComponents(string: "https://api.telegram.org/bot\(botToken)/getUpdates")!
        comps.queryItems = [
            URLQueryItem(name: "offset", value: "\(offset)"),
            URLQueryItem(name: "timeout", value: "\(timeout)"),
        ]
        guard let url = comps.url else { return nil }
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Double(timeout) + 10
        let session = URLSession(configuration: config)
        do {
            let (data, response) = try await session.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
            let decoded = try JSONDecoder().decode(TelegramResponse.self, from: data)
            return decoded.ok ? decoded.result : nil
        } catch {
            return nil
        }
    }

    @MainActor private func notifyMessage(_ text: String) { onMessage(text) }
    @MainActor private func notifyStatus(_ s: String) { onStatusChange(s) }
}
