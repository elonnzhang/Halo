import AppKit
@preconcurrency import ApplicationServices
import HaloCore

/// Read / write the `AXFullScreen` attribute on a target app's focused
/// window. Requires Accessibility trust; callers must check
/// `AXPermissionGate.isTrusted` first and surface the trust prompt
/// themselves when needed (we don't want this util to side-effect prompts
/// during a render snapshot).
///
/// `AXFullScreen` is a private constant (`kAXFullScreenAttribute` doesn't
/// exist in the public headers) but has been stable since macOS 10.7 and
/// is the same API Magnet / Rectangle / Raycast use.
///
/// `@MainActor` because the CFString attribute name isn't `Sendable` and
/// all Halo callers are main-actor already.
@MainActor
public enum FullScreenToggler {
    private static let fullScreenAttr = "AXFullScreen" as CFString

    /// Best-effort read. Returns false on any failure (AX not granted,
    /// app has no focused window, attribute missing). Cheap enough to
    /// call once per arc summon.
    public static func isFullscreen(forPID pid: pid_t) -> Bool {
        guard AXPermissionGate.isTrusted else { return false }
        let app = AXUIElementCreateApplication(pid)
        guard let win = focusedWindow(of: app) else { return false }
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(win, fullScreenAttr, &value)
        guard err == .success else { return false }
        return (value as? Bool) ?? false
    }

    /// Toggle the fullscreen state of the target app's focused window.
    /// Returns true on success. Failure modes: no AX trust, no focused
    /// window, attribute write rejected (e.g. fullscreen-locked app).
    @discardableResult
    public static func toggle(forPID pid: pid_t) -> Bool {
        guard AXPermissionGate.isTrusted else { return false }
        let app = AXUIElementCreateApplication(pid)
        guard let win = focusedWindow(of: app) else { return false }
        var current: AnyObject?
        AXUIElementCopyAttributeValue(win, fullScreenAttr, &current)
        let isFs = (current as? Bool) ?? false
        let err = AXUIElementSetAttributeValue(win, fullScreenAttr, (!isFs) as CFBoolean)
        return err == .success
    }

    private static func focusedWindow(of app: AXUIElement) -> AXUIElement? {
        var value: AnyObject?
        let err = AXUIElementCopyAttributeValue(
            app, kAXFocusedWindowAttribute as CFString, &value
        )
        guard err == .success, let value = value else { return nil }
        // CF bridge: AXUIElement is its own toll-free type. Force-cast
        // through `AnyObject` is the documented idiom — AX API returns
        // CFTypeRef so the cast unwraps to AXUIElement.
        return (value as! AXUIElement)
    }
}
