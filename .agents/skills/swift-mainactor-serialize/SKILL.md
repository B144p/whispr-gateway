---
name: swift-mainactor-serialize
description: >
  Serializes @MainActor async operations in Swift using a pending-task chain to prevent
  interleaving at await suspension points. Use this skill whenever you need to protect a
  save/restore pattern, clipboard access, file writes, or any side-effecting operation
  from concurrent callers on a @MainActor class. Apply it when async methods on a
  @MainActor type could be called in rapid succession and incorrect interleaving would
  corrupt state — for example, two callers each saving state before the first has had a
  chance to restore it.
---

## The Problem

Swift's `@MainActor` guarantees single-threaded access *between* suspension points, but
not *across* them. When an `async` method yields with `await`, another caller can enter
the same method. If both callers share a save/restore cycle — e.g. save clipboard →
mutate → restore clipboard — the second caller's *save* runs while the first caller's
mutation is still live, capturing the wrong state. The first caller's *restore* then
puts that wrong state back, leaving stale data behind.

```
Caller A: save(original) → set(A) → yield
Caller B:                            save(A) ← WRONG
Caller B:                            set(B) → yield
Caller A:                                      sendCmdV → yield
Caller B:                                                 sendCmdV → restore(A) ← STALE
Caller A:                                                             restore(original)
```

## The Fix: Pending-Task Chain

Make the public entry point **synchronous**. It captures the current in-flight task,
then creates a new task that awaits the previous one before doing any work.

```swift
@MainActor
final class MyService {
    private var pending: Task<Void, Never>?

    // Synchronous — callers fire-and-forget; ordering is guaranteed.
    func doWork(with input: String) {
        let previous = pending
        pending = Task {
            await previous?.value   // wait for prior operation to fully complete
            await performWork(input: input)
        }
    }

    private func performWork(input: String) async {
        let saved = saveState()
        applyMutation(input)
        try? await Task.sleep(nanoseconds: 100_000_000)
        triggerSideEffect()
        try? await Task.sleep(nanoseconds: 200_000_000)
        restoreState(saved)         // always captures the correct pre-call state
    }
}
```

### Why it works

Each new task holds a reference to `previous` at the moment `doWork` is called. The
chain is: Task-N awaits Task-(N-1), which awaits Task-(N-2), and so on. Because
`performWork` only starts after the previous task completes, `saveState()` always runs
against the actual pre-call state, never against a mid-operation mutation from a
concurrent caller.

### Caller-side update

Because the public method is now synchronous, call sites that previously did:

```swift
Task { await service.doWork(with: text) }
```

simplify to:

```swift
service.doWork(with: text)       // no Task wrapper needed
```

## When to apply

- Any `@MainActor` class where an `async` method has a save/restore or
  read-modify-write cycle and can be called concurrently.
- Clipboard operations, file writes, network state mutations, UI animations with
  cleanup — any pattern where intermediate state must not be observed by a concurrent
  caller's save step.

## When NOT to apply

- Operations that are truly independent and safe to run concurrently.
- Cases where you want the *latest* call to cancel the previous one — use
  `previous?.cancel()` instead of `await previous?.value`.
- Cases requiring a bounded queue with back-pressure — use `AsyncChannel` or
  `AsyncStream` from Swift Concurrency extras instead.
