import Foundation
#if canImport(AppKit)
import AppKit
#endif

public protocol AppRuntime: Sendable {
    func isRunning(bundleID: String) -> Bool
    func activate(bundleID: String) -> Bool
    func launch(bundleID: String) -> Bool

    /// Async variants used by `Switcher.switchToAsync(bundleID:)`. The
    /// default implementations forward to the synchronous methods so
    /// existing test fakes don't have to change — but real runtimes
    /// (NSWorkspaceRuntime) override these so the caller can know
    /// whether `openApplication` actually succeeded instead of returning
    /// optimistic `true` synchronously.
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

#if canImport(AppKit)
public struct NSWorkspaceRuntime: AppRuntime {
    public init() {}

    public func isRunning(bundleID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    public func activate(bundleID: String) -> Bool {
        guard let url = bundleURL(for: bundleID) else { return false }
        return openOptimistic(url: url)
    }

    public func launch(bundleID: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return false }
        return openOptimistic(url: url)
    }

    public func activateAsync(bundleID: String) async -> Bool {
        guard let url = bundleURL(for: bundleID) else { return false }
        return await openAndAwait(url: url)
    }

    public func launchAsync(bundleID: String) async -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return false }
        return await openAndAwait(url: url)
    }

    /// macOS 14+ cooperative activation silently drops
    /// `NSRunningApplication.activate(options:)` when the caller is an
    /// LSUIElement menu-bar app that isn't frontmost. Routing through
    /// `NSWorkspace.openApplication` handles the cooperative hint for
    /// both running and not-yet-running targets. We prefer the running
    /// instance's bundle URL so we don't relaunch a relocated binary.
    private func bundleURL(for bundleID: String) -> URL? {
        let runningURL = NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleID }?.bundleURL
        return runningURL ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
    }

    /// Fire-and-forget — kicks off `openApplication`, returns true.
    /// Used by the synchronous `switchTo` path that doesn't care about
    /// the real outcome and just needs to not block the main thread.
    private func openOptimistic(url: URL) -> Bool {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
        return true
    }

    /// Wraps `openApplication`'s completion handler in a continuation so
    /// the caller (`switchToAsync`) can await the real result. The Halo
    /// fade-out can run concurrently because the awaiter is a Task; the
    /// main thread isn't blocked while suspended.
    private func openAndAwait(url: URL) async -> Bool {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        return await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
            NSWorkspace.shared.openApplication(at: url, configuration: config) { app, error in
                if let error = error {
                    HaloLog.switcher.error("openApplication failed: \(error.localizedDescription)")
                    continuation.resume(returning: false)
                } else {
                    continuation.resume(returning: app != nil)
                }
            }
        }
    }
}

extension Switcher {
    public static func live() -> Switcher { Switcher(runtime: NSWorkspaceRuntime()) }
}
#endif
