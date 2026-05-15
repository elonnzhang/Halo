import Foundation

/// What the user-bound custom Action Arc chip does when triggered. v2
/// keeps the surface to three local mechanisms; all of them target a
/// specific app (the one the arc is anchored to) so the chip lives inside
/// the per-app context the arc establishes.
public enum HaloActionKind: String, Codable, Sendable, CaseIterable {
    /// Send a key combo (e.g. ⌘N) to the target app. Halo activates the
    /// app first, then posts the keystroke via `CGEvent`. Requires
    /// Accessibility permission.
    case keyboardShortcut
    /// Run a named macOS Shortcut via `shortcuts://run-shortcut?name=…`.
    /// The Shortcuts app handles permission prompts; Halo just fires the
    /// URL.
    case runShortcut
    /// Run an AppleScript snippet via `NSAppleScript`. Halo executes the
    /// script as-is; if the script controls other apps the user will see
    /// each app's Apple Events permission prompt on first use.
    case appleScript

    /// Default SF Symbol drawn on the chip when the user hasn't picked one.
    public var defaultSFSymbol: String {
        switch self {
        case .keyboardShortcut: return "keyboard"
        case .runShortcut:      return "wand.and.stars"
        case .appleScript:      return "applescript"
        }
    }
}

/// One bound action displayed on Halo's Action Arc as the per-app custom
/// chip. `id` is stable across edits so the renderer can animate slot
/// reordering without flicker.
public struct HaloAction: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var label: String
    public var kind: HaloActionKind
    public var payload: String
    /// Optional user override; nil falls back to `kind.defaultSFSymbol`.
    public var sfSymbol: String?

    public init(
        id: UUID = UUID(),
        label: String,
        kind: HaloActionKind,
        payload: String,
        sfSymbol: String? = nil
    ) {
        self.id = id
        self.label = label
        self.kind = kind
        self.payload = payload
        self.sfSymbol = sfSymbol
    }

    /// The symbol the renderer should draw — user override if set, otherwise kind default.
    public var effectiveSFSymbol: String {
        sfSymbol?.isEmpty == false ? sfSymbol! : kind.defaultSFSymbol
    }
}
