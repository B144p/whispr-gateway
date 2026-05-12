import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var configManager: ConfigManager!
    private var menuBarController: MenuBarController!
    private var pasteService: PasteService!
    private var poller: TelegramPoller?
    private var config: AppConfig?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configManager = ConfigManager()
        guard let loaded = configManager.loadOrPrompt() else { return }
        config = loaded
        pasteService = PasteService()
        menuBarController = MenuBarController()
        menuBarController.onToggle = { [weak self] in self?.handleToggle() }
        pasteService.requestAccessibilityIfNeeded()
    }

    func applicationWillTerminate(_ notification: Notification) {
        poller?.stop()
    }

    private func handleToggle() {
        menuBarController.isActive ? deactivate() : activate()
    }

    private func activate() {
        guard let config else { return }
        menuBarController.setActive(true)
        menuBarController.setStatusText("Status: Starting…")
        let p = TelegramPoller(
            botToken: config.botToken,
            chatID: Int(config.chatID) ?? 0,
            onMessage: { [weak self] text in self?.handleMessage(text) },
            onStatusChange: { [weak self] status in
                guard self?.menuBarController.isActive == true else { return }
                self?.menuBarController.setStatusText(status)
            }
        )
        poller = p
        p.start()
        menuBarController.setStatusText("Status: Active")
    }

    private func deactivate() {
        poller?.stop()
        poller = nil
        menuBarController.setActive(false)
    }

    private func handleMessage(_ text: String) {
        menuBarController.setLastMessage(text)
        pasteService.paste(text: text)
    }
}
