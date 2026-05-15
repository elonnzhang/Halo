import AppKit
import HaloCore

/// macOS-backed `ArcRuntime`. Bundles three sources: `NSRunningApplication`
/// for quit/hide, `FullScreenToggler` (AX) for fullscreen, and the existing
/// `ActionExecutor` for the user's per-app custom chip.
public struct NSWorkspaceArcRuntime: ArcRuntime {
    private let actionExecutor: ActionExecutor

    public init(actionExecutor: ActionExecutor = .live()) {
        self.actionExecutor = actionExecutor
    }

    public func quit(bundleID: String) -> Bool {
        guard let app = runningApp(bundleID: bundleID) else { return false }
        return app.terminate()
    }

    public func hide(bundleID: String) -> Bool {
        guard let app = runningApp(bundleID: bundleID) else { return false }
        return app.hide()
    }

    public func toggleFullscreen(bundleID: String) -> Bool {
        guard let app = runningApp(bundleID: bundleID) else { return false }
        return FullScreenToggler.toggle(forPID: app.processIdentifier)
    }

    public func executeCustom(_ action: HaloAction, forBundleID bundleID: String) -> ActionOutcome {
        actionExecutor.execute(action, forBundleID: bundleID)
    }

    private func runningApp(bundleID: String) -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }
    }
}

extension ArcExecutor {
    /// Factory for the production macOS runtime.
    public static func live() -> ArcExecutor {
        ArcExecutor(runtime: NSWorkspaceArcRuntime())
    }
}
