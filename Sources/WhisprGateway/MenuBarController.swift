import AppKit

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private let toggleItem: NSMenuItem
    private let statusLabel: NSMenuItem
    private let lastMessageItem: NSMenuItem
    // Must be retained here — NSMenuItem.target is a weak reference.
    private var toggleTarget: MenuActionTarget?

    private(set) var isActive: Bool = false
    var onToggle: (() -> Void)?

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu = NSMenu()
        toggleItem = NSMenuItem(title: "Activate", action: nil, keyEquivalent: "")
        statusLabel = NSMenuItem(title: "Status: Inactive", action: nil, keyEquivalent: "")
        statusLabel.isEnabled = false
        lastMessageItem = NSMenuItem(title: "No messages yet", action: nil, keyEquivalent: "")
        lastMessageItem.isEnabled = false

        menu.addItem(toggleItem)
        menu.addItem(.separator())
        menu.addItem(statusLabel)
        menu.addItem(.separator())
        menu.addItem(lastMessageItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        let target = MenuActionTarget { [weak self] in self?.onToggle?() }
        toggleTarget = target
        toggleItem.target = target
        toggleItem.action = #selector(MenuActionTarget.trigger)

        statusItem.menu = menu
        updateIcon(active: false)
    }

    func setActive(_ active: Bool) {
        isActive = active
        toggleItem.title = active ? "Inactivate" : "Activate"
        statusLabel.title = "Status: \(active ? "Active" : "Inactive")"
        updateIcon(active: active)
    }

    func setStatusText(_ text: String) {
        statusLabel.title = text
    }

    func setLastMessage(_ text: String) {
        let preview = text.count > 40 ? String(text.prefix(40)) + "…" : text
        lastMessageItem.title = "Last: \"\(preview)\""
    }

    private func updateIcon(active: Bool) {
        guard let button = statusItem.button else { return }
        let name = active ? "mic.fill" : "mic"
        let img = NSImage(systemSymbolName: name, accessibilityDescription: "Whispr Gateway")
        img?.isTemplate = !active
        button.image = img
    }
}

// Bridges NSMenuItem's ObjC selector dispatch to a Swift closure.
private final class MenuActionTarget: NSObject {
    private let action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
    @objc func trigger() { action() }
}
