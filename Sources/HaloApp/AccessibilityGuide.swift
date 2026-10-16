import AppKit
import PermissionFlow

/// Walks the user through granting Accessibility: opens Privacy & Security →
/// Accessibility and floats a drag-to-authorize panel over System Settings
/// (PermissionFlow). Replaces the bare `AXIsProcessTrustedWithOptions` dialog.
@MainActor
final class AccessibilityGuide {
    /// App activation is asynchronous. Waiting for the pre-summon app to
    /// become frontmost again lets PermissionFlow record *it*, not Halo, as
    /// the app to return to when the panel's close button is pressed.
    private static let focusSettleDelay: Duration = .milliseconds(200)

    private var controller: PermissionFlowController?

    /// `languageOverride` is `AppPreferences.appLanguageOverride`; `nil`
    /// follows the system language, matching the rest of Halo's UI.
    func present(languageOverride: String?) {
        let origin = NSEvent.mouseLocation
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.focusSettleDelay)
            self?.authorize(from: origin, languageOverride: languageOverride)
        }
    }

    private func authorize(from origin: CGPoint, languageOverride: String?) {
        let controller = self.controller ?? PermissionFlow.makeController()
        self.controller = controller
        controller.setLocaleIdentifier(languageOverride)
        controller.authorize(
            pane: .accessibility,
            suggestedAppURLs: [Bundle.main.bundleURL],
            sourceFrameInScreen: CGRect(x: origin.x - 16, y: origin.y - 16, width: 32, height: 32)
        )
    }
}
