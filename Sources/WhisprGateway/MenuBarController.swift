import AppKit

@MainActor
final class MenuBarController {
    private let statusItem: NSStatusItem
    private let menu: NSMenu
    private let switchView: ToggleSwitchView
    private let statusLabel: NSMenuItem
    private let lastMessageItem: NSMenuItem

    private(set) var isActive: Bool = false
    var onToggle: (() -> Void)? {
        didSet { switchView.onToggle = onToggle }
    }

    init() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        menu = NSMenu()

        switchView = ToggleSwitchView()
        let switchItem = NSMenuItem()
        switchItem.view = switchView

        statusLabel = NSMenuItem(title: "Status: Inactive", action: nil, keyEquivalent: "")
        statusLabel.isEnabled = false
        lastMessageItem = NSMenuItem(title: "No messages yet", action: nil, keyEquivalent: "")
        lastMessageItem.isEnabled = false

        menu.addItem(switchItem)
        menu.addItem(.separator())
        menu.addItem(statusLabel)
        menu.addItem(.separator())
        menu.addItem(lastMessageItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
        updateIcon(active: false)
    }

    func setActive(_ active: Bool) {
        isActive = active
        switchView.setState(active)
        statusLabel.title = "Status: \(active ? "Active" : "Inactive")"
        updateIcon(active: active)
    }

    func setStatusText(_ text: String) {
        statusLabel.title = text
    }

    func setLastMessage(_ text: String) {
        let preview = text.count > 40 ? String(text.prefix(40)) + "..." : text
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

// NSSwitch + label embedded in a menu item custom view.
private final class ToggleSwitchView: NSView {
    private let label = NSTextField(labelWithString: "Active")
    private let toggle = NSSwitch()
    var onToggle: (() -> Void)?

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 200, height: 30))

        label.font = .menuFont(ofSize: 0)
        label.textColor = .labelColor
        label.translatesAutoresizingMaskIntoConstraints = false

        toggle.translatesAutoresizingMaskIntoConstraints = false
        toggle.target = self
        toggle.action = #selector(switchChanged)

        addSubview(label)
        addSubview(toggle)

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            toggle.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            toggle.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    func setState(_ active: Bool) {
        toggle.state = active ? .on : .off
    }

    @objc private func switchChanged() {
        // Let AppDelegate drive the final state back via setActive() —
        // don't sync toggle.state here to avoid fighting with error rollback.
        onToggle?()
    }
}
