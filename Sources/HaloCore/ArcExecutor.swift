import Foundation

/// Platform contract for the Action Arc. Each runtime method is a single
/// system effect; the executor sequences them based on `ArcChip` and the
/// target app. Lives in HaloCore so the dispatch logic can be unit-tested
/// without AppKit — the macOS-backed live impl is in HaloUI.
public protocol ArcRuntime: Sendable {
    /// Send terminate() to the running app. False when no running instance.
    func quit(bundleID: String) -> Bool
    /// Hide the running app. False when no running instance / rejected.
    func hide(bundleID: String) -> Bool
    /// Toggle the focused window's `AXFullScreen` attribute. Caller must
    /// have verified AX trust first; this returns false on no-AX too,
    /// but the AppDelegate gate already short-circuits the
    /// permission-prompt path before getting here.
    func toggleFullscreen(bundleID: String) -> Bool
    /// Execute the user's custom action through `ActionExecutor`. The
    /// bundleID is forwarded so keystroke actions can activate + target
    /// the bound app.
    func executeCustom(_ action: HaloAction, forBundleID bundleID: String) -> ActionOutcome
}

public struct ArcExecutor: Sendable {
    private let runtime: ArcRuntime

    public init(runtime: ArcRuntime) {
        self.runtime = runtime
    }

    @discardableResult
    public func execute(chip: ArcChip, forBundleID bundleID: String) -> ActionOutcome {
        switch chip {
        case .builtin(.quit):
            let ok = runtime.quit(bundleID: bundleID)
            HaloLog.switcher.info("arc quit \(bundleID) → \(ok ? "ok" : "FAILED")")
            return ok ? .executed : .failed

        case .builtin(.hide):
            let ok = runtime.hide(bundleID: bundleID)
            HaloLog.switcher.info("arc hide \(bundleID) → \(ok ? "ok" : "FAILED")")
            return ok ? .executed : .failed

        case .builtin(.fullscreenToggle):
            let ok = runtime.toggleFullscreen(bundleID: bundleID)
            HaloLog.switcher.info("arc fullscreen \(bundleID) → \(ok ? "ok" : "FAILED")")
            return ok ? .executed : .failed

        case .custom(let action):
            return runtime.executeCustom(action, forBundleID: bundleID)

        case .emptyCustom:
            // The AppDelegate routes empty-custom to Settings before
            // commit reaches the executor; if we still see it here treat
            // as no-op success so we don't shake-and-fail spuriously.
            return .executed
        }
    }
}
