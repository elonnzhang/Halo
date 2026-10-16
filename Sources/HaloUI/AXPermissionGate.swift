import ApplicationServices

/// Thin wrapper around the global Accessibility trust check. Only the
/// fullscreen-toggle chip in the Action Arc needs AX; the rest of Halo's
/// core path stays AX-free, so reads should be cheap and one-shot.
///
/// Asking the user to grant trust lives in HaloApp (`AccessibilityGuide`),
/// because it depends on a UI-bearing third-party package.
public enum AXPermissionGate {
    /// True when the current process is currently trusted to drive other
    /// apps via the Accessibility API. Cheap — backed by an OS query.
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }
}
