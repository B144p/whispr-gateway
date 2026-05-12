---
name: macos-menubar-spm
description: >
  Patterns and pitfalls for building a macOS menu-bar-only app using Swift Package
  Manager (no Xcode project file) with Swift 6 strict concurrency. Use this skill
  whenever working on a macOS app that lives in the menu bar, uses NSStatusItem,
  needs AppKit without SwiftUI, or is built purely with SPM. Also applies when
  debugging Swift 6 concurrency errors in AppKit code, wiring NSMenuItem selectors
  to Swift closures, or integrating Accessibility/CGEvent APIs.
---

# macOS Menu Bar App — Swift Package Manager + Swift 6

Patterns derived from building a real menu-bar-only macOS app (no Xcode project, no
`.xcodeproj`, pure `swift build` / `swift run` workflow) under Swift 6 strict
concurrency checking.

---

## 1. Package.swift — always declare platform

```swift
// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MyApp",
    platforms: [.macOS(.v13)],   // ← required
    targets: [
        .executableTarget(name: "MyApp"),
    ]
)
```

Without `platforms:`, the compiler doesn't know the deployment target and emits
availability warnings for AppKit APIs, SF Symbols (`NSImage(systemSymbolName:)`),
and async/await on macOS. `.macOS(.v13)` is a safe baseline — lower it to `.v12` if
you need Monterey support.

---

## 2. Entry point — use `main.swift`, not `@main`

In SPM, `main.swift` is the designated entry point for top-level executable code.
Do **not** use `@main` on a struct or class — you cannot have both in the same
target (compile error: *'main' attribute cannot be used in a module that contains
top-level code*).

```swift
// Sources/MyApp/main.swift
import AppKit

let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // hide from Dock before run()
let delegate = AppDelegate()
app.delegate = delegate
app.run()                              // blocks forever, drives RunLoop
```

`app.run()` is synchronous and never returns — this is correct. All other files in
the target are regular Swift files (no `@main`, no top-level code).

---

## 3. Hide from Dock — `.accessory` activation policy

```swift
app.setActivationPolicy(.accessory)
```

Call this **before** `app.run()`. This makes the app a "background app": no Dock
icon, no app menu, no main window. The only UI surface is the `NSStatusItem` in the
menu bar. Calling it after `run()` (e.g., in `applicationDidFinishLaunching`) is too
late on some macOS versions and can cause a brief Dock icon flash.

---

## 4. AppDelegate — mark `@MainActor`

```swift
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) { ... }
}
```

`NSApplicationDelegate` methods are always called on the main thread. Marking the
class `@MainActor` makes this explicit and lets you store `@MainActor`-isolated
objects (menu bar controller, paste service, etc.) without actor-isolation warnings.

---

## 5. NSMenuItem selector — retain the target

`NSMenuItem.target` is a **weak** `AnyObject?` reference in AppKit. If you set it
to an object that has no other owner, it is deallocated immediately and the action
silently never fires.

**Broken:**
```swift
toggleItem.target = MenuActionTarget { ... }   // deallocated immediately!
toggleItem.action = #selector(MenuActionTarget.trigger)
```

**Correct — store a strong reference:**
```swift
@MainActor
final class MenuBarController {
    private var toggleTarget: MenuActionTarget?   // keeps it alive

    init() {
        let target = MenuActionTarget { [weak self] in self?.onToggle?() }
        toggleTarget = target          // strong ref
        toggleItem.target = target
        toggleItem.action = #selector(MenuActionTarget.trigger)
    }
}

// Bridge from ObjC selector to Swift closure
private final class MenuActionTarget: NSObject {
    private let action: () -> Void
    init(action: @escaping () -> Void) { self.action = action }
    @objc func trigger() { action() }
}
```

The `MenuActionTarget` pattern is needed because Swift 6's `@MainActor` isolation
prevents using `#selector` directly on actor-isolated methods without going through
an `NSObject` subclass.

---

## 6. Accessibility check — avoid `kAXTrustedCheckOptionPrompt` in Swift 6

`kAXTrustedCheckOptionPrompt` is a global mutable `CFStringRef` from
`ApplicationServices`. Swift 6 strict concurrency rejects it:

> *reference to var 'kAXTrustedCheckOptionPrompt' is not concurrency-safe because
> it involves shared mutable state*

**Use `AXIsProcessTrusted()` instead** — it checks without prompting, which is what
you want when you're handling the prompt yourself:

```swift
import ApplicationServices

func isAccessibilityGranted() -> Bool {
    return AXIsProcessTrusted()
}
```

To prompt the user, open System Settings directly rather than relying on the API:

```swift
let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
NSWorkspace.shared.open(url)
```

---

## 7. Polling loop — `nonisolated(unsafe)` for single-Task mutable state

When a class conforms to `Sendable` but has mutable stored properties only ever
touched inside a single `Task` (no actual concurrent access), use
`nonisolated(unsafe)` to satisfy the compiler:

```swift
final class Poller: Sendable {
    private nonisolated(unsafe) var task: Task<Void, Never>?
    private nonisolated(unsafe) var offset: Int = 0

    func start() {
        task = Task {
            // offset is only accessed here — no data race
            await pollLoop()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
    }
}
```

`nonisolated(unsafe)` tells the compiler "I accept responsibility for thread
safety." Use it only when you can reason that accesses are serialised (e.g., always
within the same `Task`, or protected by an external lock).

---

## 8. `@MainActor` callbacks from background Tasks

To deliver results from a background polling `Task` back to the main actor, type
the callback as `@Sendable @MainActor`:

```swift
final class Poller: Sendable {
    private let onMessage: @Sendable @MainActor (String) -> Void

    init(onMessage: @escaping @Sendable @MainActor (String) -> Void) {
        self.onMessage = onMessage
    }

    @MainActor private func deliver(_ text: String) {
        onMessage(text)
    }
}
```

Calling `await deliver(text)` from inside the Task hops to the main actor before
invoking the closure — no manual `DispatchQueue.main.async` needed.

---

## 9. Async paste with clipboard preservation

`Task.sleep` inside an `async` method suspends without blocking the RunLoop, so
delays between clipboard operations don't freeze the UI:

```swift
@MainActor
func paste(text: String) async {
    let pb = NSPasteboard.general
    let saved = snapshot(pb)          // copy all item data before overwriting
    pb.clearContents()
    pb.setString(text, forType: .string)
    try? await Task.sleep(nanoseconds: 100_000_000)   // 100ms settle
    sendCmdV()
    try? await Task.sleep(nanoseconds: 200_000_000)   // 200ms for paste to land
    restore(pb, saved)
}
```

Snapshot by copying raw `Data` blobs (not just the string), so the restore works
for images and files too:

```swift
private func snapshot(_ pb: NSPasteboard) -> [NSPasteboardItem] {
    return (pb.pasteboardItems ?? []).map { item in
        let copy = NSPasteboardItem()
        for type in item.types {
            if let data = item.data(forType: type) { copy.setData(data, forType: type) }
        }
        return copy
    }
}
```

---

## 10. Cmd+V via CGEvent

Virtual key `0x09` is `kVK_ANSI_V` — the physical key position, layout-independent:

```swift
private func sendCmdV() {
    let src = CGEventSource(stateID: .hidSystemState)
    let down = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
    let up   = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
    down?.flags = .maskCommand
    up?.flags   = .maskCommand
    down?.post(tap: .cgSessionEventTap)
    up?.post(tap: .cgSessionEventTap)
}
```

`CGEvent.post` silently does nothing if `AXIsProcessTrusted()` returns false — always
check Accessibility before calling it.

---

## Quick-start checklist

- [ ] `platforms: [.macOS(.v13)]` in Package.swift
- [ ] Entry point in `main.swift` (not `@main`)
- [ ] `app.setActivationPolicy(.accessory)` before `app.run()`
- [ ] `AppDelegate` marked `@MainActor`
- [ ] `MenuActionTarget` stored as a `var` property (not transient)
- [ ] Use `AXIsProcessTrusted()` (not `kAXTrustedCheckOptionPrompt`)
- [ ] `nonisolated(unsafe)` for single-Task mutable state on `Sendable` classes
- [ ] Callbacks typed as `@Sendable @MainActor (T) -> Void` for cross-actor delivery
