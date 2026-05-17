import Foundation

/// Identity of the built-in virtual "ALL" profile.
///
/// The ALL profile is rendered as the first pill in the Profile Tab Strip
/// (when `AppPreferences.showAllProfile` is on) and, when active, swaps
/// the radial wheel for a watchOS-style honeycomb grid of every installed
/// app. It is intentionally NOT stored in `AppPreferences._profiles` —
/// `BindingProfile` is user data, the ALL profile has no pin layout, and
/// every existing call site that iterates real profiles (Settings →
/// ProfileBar, the menu-bar Profile submenu, prefs serialization) stays
/// correct without filtering.
///
/// Lives in HaloUI rather than HaloCore so the virtual-profile concept
/// doesn't bleed into the data layer.
public enum GridProfile {
    /// Fixed UUID so the constant is stable across launches and across
    /// any persistence we add later. Chosen as `…0001` to be visually
    /// distinguishable from the `UUID()` values BindingProfile uses.
    public static let id: UUID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    /// Display name for the pill (and accessibility label fallback).
    /// Kept short — the pill renders an SF Symbol, but VoiceOver and
    /// the Settings sidebar strip both read this.
    public static let displayName: String = "ALL"
}
