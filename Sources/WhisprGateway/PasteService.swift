import AppKit
import ApplicationServices

@MainActor
final class PasteService {
    private var pending: Task<Void, Never>?

    func isAccessibilityGranted() -> Bool {
        return AXIsProcessTrusted()
    }

    func requestAccessibilityIfNeeded() {
        guard !isAccessibilityGranted() else { return }
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = """
            Whispr Gateway needs Accessibility access to simulate keyboard input.

            System Settings → Privacy & Security → Accessibility → enable Whispr Gateway
            """
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open System Settings")
        alert.addButton(withTitle: "Later")
        if alert.runModal() == .alertFirstButtonReturn {
            let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
            NSWorkspace.shared.open(url)
        }
    }

    // Enqueue pastes serially so concurrent messages don't interleave their
    // save/restore cycle and leave stale telegram text on the clipboard.
    func paste(text: String) {
        let previous = pending
        pending = Task {
            await previous?.value
            await performPaste(text: text)
        }
    }

    private func performPaste(text: String) async {
        guard isAccessibilityGranted() else {
            requestAccessibilityIfNeeded()
            return
        }
        let pasteboard = NSPasteboard.general
        let saved = savePasteboard(pasteboard)
        pasteboard.clearContents()
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        // Mark as transient so clipboard managers skip recording it in history.
        item.setData(Data(), forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        pasteboard.writeObjects([item])
        try? await Task.sleep(nanoseconds: 100_000_000)
        sendCmdV()
        try? await Task.sleep(nanoseconds: 200_000_000)
        restorePasteboard(pasteboard, contents: saved)
    }

    private func savePasteboard(_ pb: NSPasteboard) -> [NSPasteboardItem] {
        var items: [NSPasteboardItem] = []
        for item in pb.pasteboardItems ?? [] {
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) {
                    copy.setData(data, forType: type)
                }
            }
            items.append(copy)
        }
        return items
    }

    private func restorePasteboard(_ pb: NSPasteboard, contents: [NSPasteboardItem]) {
        pb.clearContents()
        if !contents.isEmpty { pb.writeObjects(contents) }
    }

    private func sendCmdV() {
        let src = CGEventSource(stateID: .hidSystemState)
        // 0x09 = kVK_ANSI_V — physical key position, layout-independent
        let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        let up   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        down?.flags = .maskCommand
        up?.flags   = .maskCommand
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }
}
