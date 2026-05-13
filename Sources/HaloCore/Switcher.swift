import Foundation
#if canImport(AppKit)
import AppKit
#endif

public protocol AppRuntime: Sendable {
    func isRunning(bundleID: String) -> Bool
    func activate(bundleID: String) -> Bool
    func launch(bundleID: String) -> Bool
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
}

#if canImport(AppKit)
public struct NSWorkspaceRuntime: AppRuntime {
    public init() {}

    public func isRunning(bundleID: String) -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleID }
    }

    public func activate(bundleID: String) -> Bool {
        // macOS 14+ cooperative activation silently drops
        // NSRunningApplication.activate(options:) when the caller is an
        // LSUIElement menu-bar app that isn't frontmost. Routing through
        // NSWorkspace.openApplication handles the cooperative hint correctly
        // for both running and not-yet-running targets. We still prefer the
        // bundle URL of the running instance so we don't relaunch a relocated
        // binary.
        let runningURL = NSWorkspace.shared.runningApplications
            .first { $0.bundleIdentifier == bundleID }?.bundleURL
        guard let url = runningURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return false }
        return openAndActivate(url: url)
    }

    public func launch(bundleID: String) -> Bool {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return false }
        return openAndActivate(url: url)
    }

    private func openAndActivate(url: URL) -> Bool {
        // Fire-and-forget: DispatchGroup.wait here blocked the main thread long
        // enough for the Halo fade-out to stall. openApplication handles the
        // cooperative-activation hint in the background; optimistically return
        // true once we've kicked it off. Sync failure (bundle-not-found) still
        // returns false via the nil-url check above.
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config, completionHandler: nil)
        return true
    }
}

extension Switcher {
    public static func live() -> Switcher { Switcher(runtime: NSWorkspaceRuntime()) }
}
#endif
