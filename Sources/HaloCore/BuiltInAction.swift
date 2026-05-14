import Foundation

/// The three system-built-in actions that always sit on the arc (positions
/// 0/1/2). Position is stable across every app so the user builds muscle
/// memory: "red is quit, yellow is fullscreen, blue is hide" no matter
/// which app you summoned the arc on.
public enum BuiltInActionKind: String, Codable, Sendable, CaseIterable {
    case quit
    case fullscreenToggle
    case hide

    /// SF Symbol; for fullscreen the renderer chooses between two glyphs
    /// based on the target app's current fullscreen state, so this base
    /// glyph is "enter fullscreen" and the renderer overrides when the
    /// app is already fullscreen.
    public var sfSymbol: String {
        switch self {
        case .quit:             return "power"
        case .fullscreenToggle: return "arrow.up.left.and.arrow.down.right"
        case .hide:             return "moon"
        }
    }

    /// SF Symbol used when the app is already fullscreen. Only meaningful
    /// for `.fullscreenToggle`; the other cases return their base glyph.
    public var sfSymbolAlt: String {
        switch self {
        case .fullscreenToggle: return "arrow.down.right.and.arrow.up.left"
        default:                return sfSymbol
        }
    }

    public var displayLabel: String {
        switch self {
        case .quit:             return NSLocalizedString("Quit", comment: "Arc chip")
        case .fullscreenToggle: return NSLocalizedString("Fullscreen", comment: "Arc chip")
        case .hide:             return NSLocalizedString("Hide", comment: "Arc chip")
        }
    }

    /// Display label rendered when the app is already fullscreen.
    public var displayLabelAlt: String {
        switch self {
        case .fullscreenToggle: return NSLocalizedString("Exit Fullscreen", comment: "Arc chip when already fullscreen")
        default:                return displayLabel
        }
    }

    /// True when this action requires Accessibility permission. Renderer
    /// uses this to render a gated state when `AXPermissionGate.isTrusted`
    /// is false.
    public var requiresAX: Bool {
        switch self {
        case .fullscreenToggle: return true
        case .quit, .hide:      return false
        }
    }
}

/// One chip on the arc. Position 0..2 are built-ins; position 3 is either
/// a user-bound `HaloAction` or the `+ Add` placeholder.
public enum ArcChip: Equatable, Sendable {
    case builtin(BuiltInActionKind)
    case custom(HaloAction)
    case emptyCustom
}

/// Snapshot of the arc when it was summoned. Captured once at trigger time
/// so render decisions (toggle icon, gated state) don't depend on
/// re-querying the target app on every redraw.
public struct ActiveArc: Equatable, Sendable {
    public let slotIndex: Int
    public let bundleID: String
    public let appName: String
    public let chips: [ArcChip]
    /// Was the target app fullscreen at trigger time? Drives the toggle
    /// chip's icon + label. Re-read on every summon, not cached across.
    public let appIsFullscreen: Bool
    /// Was AX trusted at trigger time? Drives the gated/non-gated style of
    /// the fullscreen chip.
    public let axGranted: Bool

    public init(
        slotIndex: Int,
        bundleID: String,
        appName: String,
        chips: [ArcChip],
        appIsFullscreen: Bool,
        axGranted: Bool
    ) {
        self.slotIndex = slotIndex
        self.bundleID = bundleID
        self.appName = appName
        self.chips = chips
        self.appIsFullscreen = appIsFullscreen
        self.axGranted = axGranted
    }
}
