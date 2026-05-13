import Foundation
import SwiftUI
import HaloCore

/// Source of truth for what Halo renders. Owned by HaloApp; observed by RadialView.
@MainActor
public final class HaloState: ObservableObject {
    public enum Phase: Equatable {
        case hidden
        case idle              // Halo up, no slot under cursor
        case hovering(Int)     // < 120ms in slot
        case previewing(Int)   // ≥ 120ms in slot
        case committing(Int)
    }

    @Published public var phase: Phase = .hidden
    @Published public var slots: [HaloSlot] = []
    /// Effective slot count for the current draw. Pulled from
    /// `AppPreferences.slotCount` (the user-configured max, 4...12) by
    /// default, but `AppDelegate.refreshSlots` may shrink it dynamically
    /// down to `apps + 1` (and as low as 1) when the user has no pinned
    /// apps and fewer history apps than the configured max — so the wheel
    /// shows only one "+" rather than a ring of empty placeholders.
    @Published public var slotCount: Int = 8 {
        didSet { precondition((1...12).contains(slotCount)) }
    }
    /// Halo origin on screen, in window coordinates.
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

    /// Move the highlighted slot by `delta` (positive = clockwise, in
    /// natural slot-index order), wrapping modulo `slotCount`. Called by
    /// AppDelegate's scrollWheel monitor when Settings → Navigation →
    /// Scroll to switch slots is on. No-op when Halo is hidden or empty.
    public func advanceSelection(by delta: Int) {
        guard slotCount > 0, phase != .hidden else { return }
        let current = currentHoverSlot ?? 0
        let next = ((current + delta) % slotCount + slotCount) % slotCount
        phase = .hovering(next)
    }

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
