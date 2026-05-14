import AppKit
@preconcurrency import ApplicationServices

/// Thin wrapper around the global Accessibility trust API. Only the
/// fullscreen-toggle chip in the Action Arc needs AX; the rest of Halo's
/// core path stays AX-free, so reads should be cheap and one-shot.
///
/// Pinned to `@MainActor` because the underlying AX globals
/// (`kAXTrustedCheckOptionPrompt`) are CFString constants that Swift 6's
/// strict concurrency can't prove Sendable. All Halo callers are on the
/// main actor already, so the annotation is free.
@MainActor
public enum AXPermissionGate {
    /// True when the current process is currently trusted to drive other
    /// apps via the Accessibility API. Cheap — backed by an OS query.
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Trigger the system trust dialog. With `prompt: true` macOS shows
    /// the "<App> would like to control your computer" sheet itself and
    /// jumps the user to Privacy & Security → Accessibility. With
    /// `prompt: false` it's a silent check (same as `isTrusted`).
    @discardableResult
    public static func requestTrust(prompt: Bool = true) -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [key: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }
}
