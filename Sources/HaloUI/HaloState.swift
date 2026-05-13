import Foundation
import SwiftUI
import HaloCore

/// Source of truth for what the HUD renders. Owned by HaloApp; observed by RadialView.
@MainActor
public final class HaloState: ObservableObject {
    public enum Phase: Equatable {
        case hidden
        case idle              // HUD up, no slot under cursor
        case hovering(Int)     // < 120ms in slot
        case previewing(Int)   // ≥ 120ms in slot
        case committing(Int)
    }

    @Published public var phase: Phase = .hidden
    @Published public var slots: [HaloSlot] = []
    @Published public var slotCount: Int = 8 {
        didSet { precondition((4...12).contains(slotCount)) }
    }
    /// HUD origin on screen, in window coordinates.
    @Published public var center: CGPoint = .zero
    /// Active ripple, when any.
    @Published public var activeRipple: RippleSignal?
    /// Bundle ID of the app that was frontmost *before* Halo summoned itself.
    /// RadialView renders this as the centre-hub icon when no slot is hovered,
    /// so the user sees "where you came from" rather than Halo's own icon
    /// (Halo activates itself on summon to receive ESC/arrow keystrokes, which
    /// makes `NSWorkspace.shared.frontmostApplication` return Halo).
    @Published public var summonOriginBundleID: String?

    /// Invoked when the user decides to commit — mouse click, keyboard Return,
    /// digit hotkey, or hotkey release. Set by the AppDelegate; not @Published
    /// because nothing in the view layer needs to observe it.
    public var onCommit: (() -> Void)?

    public init() {}

    public var currentHoverSlot: Int? {
        switch phase {
        case .hovering(let i), .previewing(let i), .committing(let i): return i
        case .idle, .hidden: return nil
        }
    }

    /// Drives `.hidden → idle → hovering(i) → previewing(i) → committing(i)`
    /// transitions from a single "what slot is under the cursor right now"
    /// input. Owned here so both the cursor timer (HaloWindow) and the
    /// fallback DragGesture (RadialView) push through the same gate.
    public func updateHover(slot: Int?) {
        switch (phase, slot) {
        case (.hidden, _):
            return
        case (_, nil):
            if phase != .idle { phase = .idle }
        case (.idle, .some(let i)),
             (.hovering, .some(let i)),
             (.previewing, .some(let i)):
            if case .hovering(let prev) = phase, prev == i { return }
            if case .previewing(let prev) = phase, prev == i { return }
            phase = .hovering(i)
        case (.committing, _):
            return
        }
    }
}

public struct HaloSlot: Identifiable, Equatable {
    public let id: Int
    public var app: AppRef?
    public var identityColor: IdentityColor
    public var runState: RunState

    public enum RunState: Equatable {
        case empty
        case running
        case launchable
        case launching
        case failed
    }

    public init(id: Int, app: AppRef?, identityColor: IdentityColor, runState: RunState) {
        self.id = id
        self.app = app
        self.identityColor = identityColor
        self.runState = runState
    }

    public static func emptySlot(id: Int, fallback: IdentityColor) -> HaloSlot {
        HaloSlot(id: id, app: nil, identityColor: fallback, runState: .empty)
    }
}

public struct RippleSignal: Equatable {
    public let color: IdentityColor
    public let startedAt: Date
    public init(color: IdentityColor, startedAt: Date = Date()) {
        self.color = color
        self.startedAt = startedAt
    }
}
