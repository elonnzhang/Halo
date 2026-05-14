import Foundation

/// Pure-Swift protocol describing the platform's "switch to a bundle"
/// operations. Lives in HaloCore so unit tests can substitute a fake
/// runtime without dragging AppKit in. The concrete macOS implementation
/// (`NSWorkspaceRuntime`) lives in HaloUI alongside the rest of the
/// AppKit-coupled surface.
public protocol AppRuntime: Sendable {
    func isRunning(bundleID: String) -> Bool
    func activate(bundleID: String) -> Bool
    func launch(bundleID: String) -> Bool

    /// Async variants used by `Switcher.switchToAsync(bundleID:)`. The
    /// default implementations forward to the synchronous methods so
    /// existing test fakes don't have to change — but real runtimes
    /// override these so the caller can know whether `openApplication`
    /// actually succeeded instead of returning optimistic `true`
    /// synchronously.
    func activateAsync(bundleID: String) async -> Bool
    func launchAsync(bundleID: String) async -> Bool
}

public extension AppRuntime {
    func activateAsync(bundleID: String) async -> Bool {
        activate(bundleID: bundleID)
    }
    func launchAsync(bundleID: String) async -> Bool {
        launch(bundleID: bundleID)
    }
}

public enum SwitchOutcome: Equatable, Sendable {
    case activated
    case launched
    case failed
}

public struct Switcher: Sendable {
    private let runtime: AppRuntime

    public init(runtime: AppRuntime) {
        self.runtime = runtime
    }

    /// Synchronous variant — kept for tests and for callers that don't
    /// care whether `openApplication` succeeds. Returns optimistic
    /// `.activated` / `.launched` for the async-completing AppKit path;
    /// callers needing real outcomes should use `switchToAsync`.
    @discardableResult
    public func switchTo(bundleID: String) -> SwitchOutcome {
        let running = runtime.isRunning(bundleID: bundleID)
        if running {
            let ok = runtime.activate(bundleID: bundleID)
            HaloLog.switcher.info("activate \(bundleID) → \(ok ? "ok" : "FAILED")")
            return ok ? .activated : .failed
        }
        let ok = runtime.launch(bundleID: bundleID)
        HaloLog.switcher.info("launch \(bundleID) → \(ok ? "ok" : "FAILED")")
        return ok ? .launched : .failed
    }

    /// Awaits the real launch / activate outcome from `NSWorkspace`.
    /// Required so `AppDelegate.commitSelection` can show shake-and-fail
    /// when the bundle URL is corrupt / quarantined / un-launchable
    /// instead of optimistically rippling + dismissing.
    @discardableResult
    public func switchToAsync(bundleID: String) async -> SwitchOutcome {
        let running = runtime.isRunning(bundleID: bundleID)
        if running {
            let ok = await runtime.activateAsync(bundleID: bundleID)
            HaloLog.switcher.info("activate \(bundleID) → \(ok ? "ok" : "FAILED")")
            return ok ? .activated : .failed
        }
        let ok = await runtime.launchAsync(bundleID: bundleID)
        HaloLog.switcher.info("launch \(bundleID) → \(ok ? "ok" : "FAILED")")
        return ok ? .launched : .failed
    }
}
