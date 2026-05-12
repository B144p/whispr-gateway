import AppKit
import Foundation

struct AppConfig: Sendable {
    let botToken: String
    let chatID: String
}

@MainActor
final class ConfigManager {
    private let configDir: URL
    private let configFile: URL

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        configDir = home.appendingPathComponent(".config/whispr-gateway")
        configFile = configDir.appendingPathComponent("config.env")
    }

    func loadOrPrompt() -> AppConfig? {
        if let config = load() { return config }
        return showSetupDialog()
    }

    func load() -> AppConfig? {
        guard let content = try? String(contentsOf: configFile, encoding: .utf8) else { return nil }
        var values: [String: String] = [:]
        for line in content.components(separatedBy: .newlines) {
            let t = line.trimmingCharacters(in: .whitespaces)
            guard !t.isEmpty, !t.hasPrefix("#") else { continue }
            let parts = t.split(separator: "=", maxSplits: 1)
            guard parts.count == 2 else { continue }
            values[String(parts[0]).trimmingCharacters(in: .whitespaces)] =
                String(parts[1]).trimmingCharacters(in: .whitespaces)
        }
        guard let token = values["BOT_TOKEN"], !token.isEmpty,
              let chatID = values["CHAT_ID"], !chatID.isEmpty else { return nil }
        return AppConfig(botToken: token, chatID: chatID)
    }

    private func showSetupDialog() -> AppConfig? {
        let alert = NSAlert()
        alert.messageText = "Whispr Gateway Setup"
        alert.informativeText = "Enter your Telegram Bot Token and Chat ID."
        alert.alertStyle = .informational

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 8

        let tokenField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        tokenField.placeholderString = "BOT_TOKEN (from @BotFather)"
        let chatIDField = NSTextField(frame: NSRect(x: 0, y: 0, width: 300, height: 24))
        chatIDField.placeholderString = "CHAT_ID (numeric)"

        stack.addArrangedSubview(tokenField)
        stack.addArrangedSubview(chatIDField)
        NSLayoutConstraint.activate([stack.widthAnchor.constraint(equalToConstant: 300)])
        alert.accessoryView = stack
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Quit")

        if alert.runModal() == .alertFirstButtonReturn {
            let token = tokenField.stringValue.trimmingCharacters(in: .whitespaces)
            let chatID = chatIDField.stringValue.trimmingCharacters(in: .whitespaces)
            guard !token.isEmpty, !chatID.isEmpty else { return nil }
            save(botToken: token, chatID: chatID)
            return AppConfig(botToken: token, chatID: chatID)
        } else {
            NSApp.terminate(nil)
            return nil
        }
    }

    private func save(botToken: String, chatID: String) {
        try? FileManager.default.createDirectory(at: configDir, withIntermediateDirectories: true)
        let content = "BOT_TOKEN=\(botToken)\nCHAT_ID=\(chatID)\n"
        try? content.write(to: configFile, atomically: true, encoding: .utf8)
    }
}
