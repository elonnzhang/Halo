import Foundation

/// Which physical key (or button) drives Halo's second, single-handed
/// trigger path. The chord registered with the global hotkey is unaffected;
/// this enum only controls the auxiliary double-tap detector.
///
/// All five cases are detectable via polling — `CGEventSource.keyState`
/// for keyCode-aware keyboard detection (preserves left/right Option +
/// Control discrimination), `NSEvent.pressedMouseButtons` bitmask for
/// middle-mouse. None of these APIs require Accessibility permission.
public enum DoubleTapTrigger: String, Codable, Sendable, CaseIterable {
    case leftOption
    case rightOption
    case command
    case control
    case middleMouse

    public var displayLabel: String {
        switch self {
        case .leftOption:  return NSLocalizedString("⌥ Option (Left)", comment: "DoubleTapTrigger label")
        case .rightOption: return NSLocalizedString("⌥ Option (Right)", comment: "DoubleTapTrigger label")
        case .command:     return NSLocalizedString("⌘ Command", comment: "DoubleTapTrigger label")
        case .control:     return NSLocalizedString("⌃ Control", comment: "DoubleTapTrigger label")
        case .middleMouse: return NSLocalizedString("Mouse 3 (Middle)", comment: "DoubleTapTrigger label")
        }
    }

    /// True when the trigger is a keyboard key polled via
    /// `CGEventSource.keyState`. The middle-mouse path polls
    /// `NSEvent.pressedMouseButtons` instead.
    public var isKeyboard: Bool {
        switch self {
        case .middleMouse: return false
        default:           return true
        }
    }
}
