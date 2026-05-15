import Foundation

/// Platform contract for executing a HaloAction. Lives in HaloCore so unit
/// tests can substitute a fake runtime; the AppKit-backed `live` impl lives
/// in HaloUI alongside `NSWorkspaceRuntime`.
public protocol ActionRuntime: Sendable {
    /// Open any URL via `NSWorkspace.open`. Used by the shortcuts:// scheme
    /// that drives `runShortcut`. Returns false when `NSWorkspace.open`
    /// reports failure.
    func openURL(_ url: URL) -> Bool

    /// Activate `bundleID` and then post a `CGEvent` keystroke at the
    /// system HID tap. Requires Accessibility permission for the keystroke
    /// half; the caller is responsible for gating on permission. Returns
    /// true after the keystroke is scheduled; activation completion is
    /// best-effort.
    func postKeystroke(_ shortcut: KeyboardShortcut, toBundleID bundleID: String) -> Bool

    /// Compile + execute an AppleScript snippet via NSAppleScript. Returns
    /// false on compile error / runtime error / Apple Events permission
    /// denied; the AppleScript itself may surface its own UI (e.g. a
    /// "Halo wants to control X" Apple Events prompt) on first run.
    func runAppleScript(_ source: String) -> Bool
}

public enum ActionOutcome: Equatable, Sendable {
    case executed
    case failed
}

public struct ActionExecutor: Sendable {
    private let runtime: ActionRuntime

    public init(runtime: ActionRuntime) {
        self.runtime = runtime
    }

    /// Run `action` in the context of `bundleID`. The arc is anchored to a
    /// specific app, so keystrokes target that app. Other kinds ignore the
    /// bundleID (Shortcut routes by name; AppleScript carries its own
    /// target inside the script).
    @discardableResult
    public func execute(_ action: HaloAction, forBundleID bundleID: String) -> ActionOutcome {
        switch action.kind {
        case .keyboardShortcut:
            guard let combo = KeyboardShortcut.parse(action.payload) else {
                HaloLog.switcher.info("action keystroke \(action.payload) → FAILED (parse)")
                return .failed
            }
            let ok = runtime.postKeystroke(combo, toBundleID: bundleID)
            HaloLog.switcher.info("action keystroke \(combo.displaySymbols) → \(bundleID) → \(ok ? "ok" : "FAILED")")
            return ok ? .executed : .failed

        case .runShortcut:
            // `shortcuts://run-shortcut?name=<name>` — system handles
            // permission prompt and "shortcut not found" UI. We treat
            // URL-open success as success; if the Shortcuts app pops a
            // "not found" toast that's its surface, not ours. URLComponents
            // takes care of percent-encoding the query value, including
            // reserved characters that bare `.urlQueryAllowed` lets through.
            let trimmed = action.payload.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                HaloLog.switcher.info("action runShortcut \(action.payload) → FAILED (empty)")
                return .failed
            }
            var components = URLComponents()
            components.scheme = "shortcuts"
            components.host = "run-shortcut"
            components.queryItems = [URLQueryItem(name: "name", value: trimmed)]
            guard let url = components.url else {
                HaloLog.switcher.info("action runShortcut \(action.payload) → FAILED (encode)")
                return .failed
            }
            let ok = runtime.openURL(url)
            HaloLog.switcher.info("action runShortcut \(action.payload) → \(ok ? "ok" : "FAILED")")
            return ok ? .executed : .failed

        case .appleScript:
            let trimmed = action.payload.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                HaloLog.switcher.info("action appleScript empty payload → FAILED")
                return .failed
            }
            let ok = runtime.runAppleScript(trimmed)
            HaloLog.switcher.info("action appleScript → \(ok ? "ok" : "FAILED")")
            return ok ? .executed : .failed
        }
    }
}
