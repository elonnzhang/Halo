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

    /// Which ring is currently rendered. Layer 1 is the existing app
    /// switcher; layer 2 (Action Ring) overlays per-app local actions while
    /// the user holds ⇧ over an app slot. See
    /// `docs/superpowers/specs/2026-05-14-action-ring-design.md`.
    public enum Layer: Equatable {
        case slots
        case actions(ActionContext)
    }

    /// Carries the bundleID + display info needed to render layer 2
    /// without the renderer reaching back into the slot array. The
    /// `originSlotIndex` is the slot the user was hovering when ⇧ was
    /// pressed — used to highlight that same index when popping back to
    /// layer 1 (spec §2).
    public struct ActionContext: Equatable {
        public let bundleID: String
        public let appName: String
        public let identityColor: IdentityColor
        public let originSlotIndex: Int
        public init(bundleID: String, appName: String, identityColor: IdentityColor, originSlotIndex: Int) {
            self.bundleID = bundleID
            self.appName = appName
            self.identityColor = identityColor
            self.originSlotIndex = originSlotIndex
        }
    }

    @Published public var phase: Phase = .hidden
    @Published public var slots: [HaloSlot] = []
    /// Layer-2 sectors for the currently-targeted app. Empty entries render
    /// as "+ Configure" placeholders (spec §7). Populated by AppDelegate's
    /// layer-toggle logic; cleared whenever `layer` returns to `.slots`.
    @Published public var actionSlots: [HaloActionSlot] = []
    @Published public var layer: Layer = .slots
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

    /// Switch into layer 2 for `context`, populating `actionSlots` from
    /// `actions` (capped at `slotCount`, padded with placeholders to fill
    /// the wheel). Phase is reset to `.hovering(originSlotIndex)` so the
    /// user lands on the same angular position they entered from. No-op
    /// when Halo is hidden.
    public func enterActionRing(_ context: ActionContext, actions: [HaloAction]) {
        guard phase != .hidden else { return }
        let cap = slotCount
        let placed: [HaloAction?] = (0..<cap).map { i in
            actions.indices.contains(i) ? actions[i] : nil
        }
        actionSlots = placed.enumerated().map { i, action in
            HaloActionSlot(id: i, action: action, identityColor: context.identityColor)
        }
        layer = .actions(context)
        let landing = min(max(0, context.originSlotIndex), cap - 1)
        phase = .hovering(landing)
    }

    /// Return to layer 1, dropping the action slots. Highlight whatever
    /// slot index we were on in layer 2 (so the user can press the hotkey
    /// to commit the same-direction app, or release ⇧ and continue moving).
    /// No-op when not currently in `.actions`.
    public func exitActionRing() {
        guard case .actions = layer else { return }
        actionSlots = []
        layer = .slots
        // Keep the angular position; if we were idle in layer 2 (cursor
        // outside the wheel), fall back to .idle.
        switch phase {
        case .hovering, .previewing, .committing:
            // currentHoverSlot already returns the right index for these,
            // so leaving phase alone keeps the highlight on the same sector.
            break
        case .idle, .hidden:
            break
        }
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
            if phase != .idle { phase = .idle }
        case (.idle, .some(let i)),
             (.hovering, .some(let i)),
             (.previewing, .some(let i)):
            if case .hovering(let prev) = phase, prev == i { return }
            if case .previewing(let prev) = phase, prev == i { return }
            phase = .hovering(i)
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

/// One sector on layer 2 (Action Ring). `action == nil` is the
/// "+ Configure"/"+ Add action" placeholder rendered when the user hasn't
/// bound an action for that index (spec §7).
public struct HaloActionSlot: Identifiable, Equatable {
    public let id: Int
    public var action: HaloAction?
    public var identityColor: IdentityColor

    public init(id: Int, action: HaloAction?, identityColor: IdentityColor) {
        self.id = id
        self.action = action
        self.identityColor = identityColor
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
