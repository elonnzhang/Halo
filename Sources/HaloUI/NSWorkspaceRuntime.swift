import AppKit
import HaloCore

/// AppKit-backed `AppRuntime`. Lives in HaloUI because HaloCore is
/// intentionally AppKit-free — keeping NSWorkspace details in this
/// module preserves HaloCore's pure-Swift surface so it stays testable
/// without dragging the macOS UI layer into the test process.
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
    /// Factory for the macOS production runtime. Lives in HaloUI because
    /// it references `NSWorkspaceRuntime`; HaloCore exposes only the
    /// `Switcher` initialiser that takes an `AppRuntime`.
    public static func live() -> Switcher { Switcher(runtime: NSWorkspaceRuntime()) }
}
