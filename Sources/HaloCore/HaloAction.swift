import Foundation

/// What kind of local resource a user-bound action opens. v1 keeps the
/// surface deliberately narrow: every kind has to be expressible as a
/// single payload string + a system-handled side effect, no shell.
public enum HaloActionKind: String, Codable, Sendable, CaseIterable {
    case openFolder      // payload: absolute file path
    case openURL         // payload: a URL with any scheme NSWorkspace accepts
    case runShortcut     // payload: Shortcut name; routed via shortcuts://run-shortcut

    /// Default SF Symbol surfaced on a sector when the user hasn't overridden one.
    public var defaultSFSymbol: String {
        switch self {
        case .openFolder:  return "folder.fill"
        case .openURL:     return "link"
        case .runShortcut: return "wand.and.stars"
        }
    }
}

/// One bound action displayed on Halo's second layer for a specific app.
/// `id` is stable across edits so the rendering layer can animate slot
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
