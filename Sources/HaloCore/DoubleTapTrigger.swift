import Foundation

/// Which physical key (or button) drives Halo's second, single-handed
/// trigger path. The chord registered with the global hotkey is unaffected;
/// this enum only controls the auxiliary double-tap detector.
public enum DoubleTapTrigger: String, Codable, Sendable, CaseIterable {
    case leftOption
    case rightOption
    case command
    case control
    case middleMouse

    /// Human-readable label for Settings → Trigger popup. Keys live in
    /// `Localizable.strings` so the popup follows the user's language.
    public var displayLabel: String {
        switch self {
        case .leftOption:   return NSLocalizedString("⌥ Option (Left)", comment: "DoubleTapTrigger label")
        case .rightOption:  return NSLocalizedString("⌥ Option (Right)", comment: "DoubleTapTrigger label")
        case .command:      return NSLocalizedString("⌘ Command", comment: "DoubleTapTrigger label")
        case .control:      return NSLocalizedString("⌃ Control", comment: "DoubleTapTrigger label")
        case .middleMouse:  return NSLocalizedString("Mouse 3 (Middle)", comment: "DoubleTapTrigger label")
        }
    }

    /// True when the trigger is a keyboard modifier read from
    /// `NSEvent.flagsChanged`. The middle-mouse path uses
    /// `NSEvent.otherMouseDown` and is the only false case.
    public var isKeyboard: Bool {
        switch self {
        case .middleMouse: return false
        default: return true
        }
    }
}
