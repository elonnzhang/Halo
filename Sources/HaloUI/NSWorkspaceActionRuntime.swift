import AppKit
@preconcurrency import Carbon
import HaloCore

/// AppKit-backed `ActionRuntime`. HaloCore stays AppKit-free so unit tests
/// don't drag the UI layer; the live impl lives here next to
/// `NSWorkspaceRuntime`.
public struct NSWorkspaceActionRuntime: ActionRuntime {
    public init() {}

    public func openURL(_ url: URL) -> Bool {
        NSWorkspace.shared.open(url)
    }

    /// Activate the target app, then schedule a key-down + key-up at the
    /// HID tap so the keystroke lands in the app's frontmost window. The
    /// 80 ms gap between activation and post is enough for cooperative
    /// activation to settle on macOS 14+; tighter than that and the
    /// keystroke occasionally hits the previously frontmost app.
    public func postKeystroke(_ shortcut: KeyboardShortcut, toBundleID bundleID: String) -> Bool {
        // Activation step: NSWorkspace.openApplication is the post-macOS-14
        // path that cooperatively activates the target; `NSRunningApplication
        // .activate(options:)` silently drops the call when the caller is
        // an LSUIElement that isn't frontmost.
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return false
        }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: config) { _, _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                Self.postKeystrokeNow(shortcut)
            }
        }
        return true   // optimistic — the activate completion is async
    }

    private static func postKeystrokeNow(_ shortcut: KeyboardShortcut) {
        let source = CGEventSource(stateID: .hidSystemState)
        let flags = CGEventFlags(rawValue: shortcut.modifierMask)
        if let down = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: true) {
            down.flags = flags
            down.post(tap: .cghidEventTap)
        }
        if let up = CGEvent(keyboardEventSource: source, virtualKey: shortcut.keyCode, keyDown: false) {
            up.flags = flags
            up.post(tap: .cghidEventTap)
        }
    }

    /// NSAppleScript executes synchronously and pops its own permission
    /// prompts (Apple Events) the first time the script touches another
    /// app. Compile errors and runtime errors both return non-nil in the
    /// out-error dictionary; either way we treat as failure.
    public func runAppleScript(_ source: String) -> Bool {
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        _ = script.executeAndReturnError(&error)
        if let error = error {
            HaloLog.switcher.info("AppleScript error: \(error)")
            return false
        }
        return true
    }
}

extension ActionExecutor {
    /// Factory for the production macOS runtime.
    public static func live() -> ActionExecutor {
        ActionExecutor(runtime: NSWorkspaceActionRuntime())
    }
}
