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
    /// Currently-summoned Action Arc. When non-nil the RadialView overlays
    /// `ActionArcView` on top of layer 1. See
    /// `docs/superpowers/specs/2026-05-14-action-ring-design.md`.
    @Published public var activeArc: ActiveArc?
    /// Which chip (0..3) is currently hovered while an arc is up.
    /// `nil` = cursor is not on any chip.
    @Published public var arcHoverChip: Int?
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

    /// Ambient tint of the currently-active profile. `nil` when the user
    /// hasn't chosen one — `RadialView` then renders no idle halo glow.
    /// AppDelegate.applyPreferences pushes this on every prefs mutation
    /// (profile switch, tint edit).
    @Published public var profileTint: IdentityColor?

    /// Profile pills rendered above the wheel. Mirrors `prefs.profiles`
    /// (id + display name only — the view doesn't need pin or override
    /// data). AppDelegate.applyPreferences pushes this on every prefs
    /// mutation so creating / renaming / deleting profiles re-flows the
    /// top strip.
    @Published public var profilePills: [ProfilePill] = []

    /// Currently-active profile id. The top strip highlights the
    /// matching pill; `Tab` / `⇧Tab` shortcut and pill taps both feed
    /// through `onSwitchProfile` below.
    @Published public var activeProfileID: UUID?

    /// Tap handler for the profile pill strip. AppDelegate wires this to
    /// `prefs.switchToProfile(...)`. `nil` outside of the HaloApp host
    /// (e.g. previews / tests) so taps are inert.
    public var onSwitchProfile: ((UUID) -> Void)?

    /// Where this summon ended up against the screen edge after clamp.
    /// Drives the profile tab strip's placement — at the top edge the
    /// strip flips below the wheel so it isn't slammed against the
    /// menu bar (and inversely at the bottom edge).
    @Published public var edgeAnchor: SummonEdgeAnchor = .none

    /// Drives the summon "explosion from centre" animation (motion ①):
    /// 0 = collapsed at the hub, 1 = full radius. `HaloWindow.summon`
    /// sets this 0→1 inside a `withAnimation` block; `RadialView` reads
    /// it to scale icons, the wheel disc, and the halo glow.
    @Published public var summonProgress: Double = 0

    /// Drives the commit "launch & fly away" animation (motion ⑤):
    /// 0 = wheel at rest, 1 = scaled out + faded. AppDelegate latches
    /// this 0→1 on commit so the wheel plays scale-up + opacity-drop in
    /// lockstep with the panel's alphaValue fade.
    @Published public var dismissProgress: Double = 0

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

    /// Optional anchor slot for the first `advanceSelection` of a summon.
    /// Set by AppDelegate when "Highlight frontmost on summon" is enabled
    /// so a single scroll tick lands on the previous frontmost app's slot.
    /// Not @Published — this is consumed by scroll logic, never rendered;
    /// writing to phase here would flash an unrelated sector through the
    /// 0.14s sector animation before the cursor poll clears it.
    public var scrollAnchor: Int?

    /// Move the highlighted slot by `delta` (positive = clockwise, in
    /// natural slot-index order), wrapping modulo `slotCount`. Called by
    /// AppDelegate's scrollWheel monitor when Settings → Navigation →
    /// Scroll to switch slots is on. No-op when Halo is hidden or empty.
    ///
    /// Anchor priority lives in `SlotCycle.nextIndex` (pure, tested).
    public func advanceSelection(by delta: Int) {
        guard slotCount > 0, phase != .hidden else { return }
        let next = SlotCycle.nextIndex(
            delta: delta,
            slotCount: slotCount,
            currentHover: currentHoverSlot,
            scrollAnchor: scrollAnchor
        )
        if SlotCycle.consumedScrollAnchor(
            currentHover: currentHoverSlot,
            scrollAnchor: scrollAnchor,
            slotCount: slotCount
        ) {
            scrollAnchor = nil
        }
        let previous = currentHoverSlot
        phase = .hovering(next)
        if previous != next {
            SoundEffectPlayer.shared.play(.slide)
        }
    }

    /// Summon the Action Arc for the given slot. No-op when Halo is hidden
    /// or `arc.chips.isEmpty`. Caller is responsible for snapshotting the
    /// app's fullscreen + AX state before calling so the renderer can
    /// pick the right toggle icon.
    public func showArc(_ arc: ActiveArc) {
        guard phase != .hidden else { return }
        activeArc = arc
        arcHoverChip = nil
    }

    /// Drop the arc back to the slot ring. Caller decides whether this is
    /// a cancel (trigger released without commit) or a post-commit cleanup.
    public func hideArc() {
        activeArc = nil
        arcHoverChip = nil
    }

    public func updateHover(slot: Int?) {
        switch (phase, slot) {
        case (.hidden, _):
            return
        // Latch committing BEFORE the nil-fallback case — otherwise a
        // cursor move during the brief commit-dismiss animation would
        // drop phase back to .idle and visually lose the scaled "slot
        // is committing" treatment. Coverage: HaloStateHoverTests.
        case (.committing, _):
            return
        case (_, nil):
            if phase != .idle {
                // Wrap in withAnimation so the `.transition()` modifiers
                // on haloGlow / labelChip / centerHubIcon (which are
                // structural conditional views) animate when they
                // disappear. Without this, the structural change pops
                // and clashes with the sector fill's own implicit
                // animation — that mismatch was the "jolt" the user
                // saw when the cursor crossed in/out of a slot.
                withAnimation(.Halo.snap()) { phase = .idle }
            }
        case (.idle, .some(let i)),
             (.hovering, .some(let i)),
             (.previewing, .some(let i)):
            if case .hovering(let prev) = phase, prev == i { return }
            if case .previewing(let prev) = phase, prev == i { return }
            withAnimation(.Halo.snap()) { phase = .hovering(i) }
            SoundEffectPlayer.shared.play(.slide)
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

/// Which screen edge the Halo panel ended up flush against after
/// `RadialPanelFrame` clamping. The profile tab strip uses this to
/// decide whether to render above or below the wheel — at the top
/// edge the strip flips downward (it would otherwise sit on the
/// menu bar); inversely at the bottom edge.
public enum SummonEdgeAnchor: String, Sendable, Equatable {
    case none
    case top
    case bottom
}

/// Lightweight projection of a `BindingProfile` for the Halo top-strip
/// renderer — name + id + optional tint colour. Avoids dragging pin
/// arrays through `@Published` (they change frequently and the strip
/// doesn't care).
public struct ProfilePill: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let tint: IdentityColor?
    public init(id: UUID, name: String, tint: IdentityColor?) {
        self.id = id
        self.name = name
        self.tint = tint
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
