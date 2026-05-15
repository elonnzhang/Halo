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
