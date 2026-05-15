import SwiftUI

/// Halo's standard animation palette. One file, one source of truth, so
/// adjusting the wheel's "feel" is a single-knob change instead of a
/// scavenger hunt across RadialView / ActionArcView / RippleView.
///
/// Every helper takes `reduceMotion: Bool` so callers can pass the
/// `\.accessibilityReduceMotion` environment value through. When reduce
/// motion is on, durations collapse to a near-instant transition (0.05s)
/// — visible enough to indicate "something happened", short enough to
/// stay under the user's vestibular threshold.
extension Animation {
    enum Halo {
        // MARK: - Cursor-tracking reactions
        //
        // Hover-style state changes the user expects to "track" their
        // cursor. Anything heavier than ~0.10s starts to feel laggy here.

        /// 0.10s easeOut — sector tint, slot icon scale, key hint scale,
        /// halo glow. The default for "I just moved my mouse".
        static func snap(reduceMotion: Bool = false) -> Animation {
            .easeOut(duration: reduceMotion ? 0.05 : 0.10)
        }

        // MARK: - Content reactions
        //
        // Reactions to a discrete user action (commit, label change) where
        // a touch of weight reads as polish rather than lag.

        /// 0.14s easeOut — label chip swap, hub icon crossfade.
        static func echo(reduceMotion: Bool = false) -> Animation {
            .easeOut(duration: reduceMotion ? 0.05 : 0.14)
        }

        // MARK: - Surface tints
        //
        // Big-area tints whose sudden change would draw the eye more than
        // the trigger that caused it. The wheel's content-aware tint is
        // the canonical case: a slight delay reads as the glass "warming
        // up" to the hovered identity colour.

        /// 0.22s easeOut — wheel content-aware tint.
        static func surface(reduceMotion: Bool = false) -> Animation {
            .easeOut(duration: reduceMotion ? 0.05 : 0.22)
        }

        // MARK: - Pop entries
        //
        // Spring entries for elements that arrive on screen rather than
        // change in place.

        /// Spring used by Action Arc chips as they fan in.
        /// response 0.30 / dampingFraction 0.72 — a hair more bouncy than
        /// the previous 0.36 / 0.78, so four chips read as "pop pop pop"
        /// rather than "fade fade fade fade".
        static func chipPop(delay: Double = 0) -> Animation {
            .spring(response: 0.30, dampingFraction: 0.72).delay(delay)
        }

        /// Welcome-window confirm bounce when the user successfully
        /// triggers the summon hotkey.
        static func confirmBounce() -> Animation {
            .spring(response: 0.40, dampingFraction: 0.70)
        }

        // MARK: - Summon / dismiss
        //
        // Motion ① (爆开) and motion ⑤ (收起) from the handoff. Both
        // drive `state.summonProgress` / `state.dismissProgress`;
        // views read those values to scale, offset, and fade. Kept as
        // timing curves (not springs) so motion holds the spec's
        // "fast-out / soft-in" hero arc — `cubic-bezier(.2,.7,.2,1.05)`
        // for summon, snappier `(.4,0,.7,.2)` for dismiss.

        /// Motion ① · Summon. 320ms, slight overshoot at the end so
        /// icons settle into place with a hair of inertia rather than
        /// parking hard at the rim.
        static func summon(reduceMotion: Bool = false) -> Animation {
            reduceMotion
                ? .easeOut(duration: 0.05)
                : .timingCurve(0.2, 0.7, 0.2, 1.05, duration: 0.32)
        }

        /// Motion ⑤ · Launch collapse. 180ms ease-in so the wheel pulls
        /// itself out fast enough that the target app's window can take
        /// over before the user perceives a delay.
        static func dismiss(reduceMotion: Bool = false) -> Animation {
            reduceMotion
                ? .easeIn(duration: 0.04)
                : .timingCurve(0.4, 0, 0.7, 0.2, duration: 0.18)
        }

        /// Motion ② · Switch (springy slot-to-slot scroll/digit jump).
        /// response 0.18 / damping 0.62 captures the "tick" of the
        /// design's `cubic-bezier(.34, 1.5, .5, 1)` without authoring
        /// a custom curve. Used for hover transitions where the user
        /// committed to a switch (digit / scroll); the slower mouse
        /// drag still uses `snap` so cursor tracking stays glued.
        static func switchSpring(reduceMotion: Bool = false) -> Animation {
            reduceMotion
                ? .easeOut(duration: 0.05)
                : .spring(response: 0.18, dampingFraction: 0.62)
        }

        // MARK: - Stagger constants
        //
        // Per-index delay multipliers for staggered entries. Living
        // alongside the springs they pair with — a future tweak stays
        // in one type instead of straddling two `Animation` extensions.

        /// Action Arc chip-to-chip stagger. 22ms × 4 chips ≈ 66ms total
        /// fan-in; combined with `chipPop` the four chips fully settle
        /// in ~150ms (vs. ~210ms previously).
        static let arcChipStagger: Double = 0.022
    }
}
