import Foundation
import CoreGraphics
import HaloCore

public enum HaloUI {
    public static let version = Halo.version

    /// Radial wheel layout — outer ring, inner hub, where icons sit, where the
    /// curved tooltip floats. Kept in one place so geometry + hit-testing +
    /// panel sizing can't drift.
    ///
    /// `haloDiameter`, `iconSize`, and `iconRadius` are now user-tunable
    /// (Settings → General → Wheel layout) and read live from
    /// `AppPreferences.shared`. SwiftUI views re-render on
    /// `objectWillChange`; `HaloWindow.summon` re-reads at every summon so
    /// changes take effect on the next invocation.
    ///
    /// Marked `@MainActor` because `AppPreferences.shared` is
    /// main-actor-isolated (it's an `ObservableObject`). Every existing
    /// call site is already on the main actor (SwiftUI view body, AppKit
    /// window setup), so the annotation costs nothing at the call site.
    @MainActor
    public enum Geometry {
        /// Outer donut diameter. User-tunable.
        public static var haloDiameter: CGFloat {
            AppPreferences.shared.haloDiameter
        }
        /// Centre hub (deadzone) diameter. Hit-tests inside are inert.
        /// Not user-tunable yet — keep the spec-locked value.
        public static let deadzoneDiameter: CGFloat = AppPreferences.layoutDeadzoneDiameter
        /// Hit-test reach: cursor positions within this diameter of the
        /// wheel centre count as a sector hover. At 1.5× the wheel
        /// diameter the cursor can sit roughly a quarter-wheel-radius
        /// outside the visible rim and still hit the sector at that
        /// angle — a comfortable cushion without losing the "drag past
        /// this circle to cancel" affordance (cursor past the reach
        /// returns nil, so releasing the trigger commits nothing).
        public static var reachDiameter: CGFloat {
            haloDiameter * 1.5
        }
        /// Visible outer rim of the disc, accounting for the soft-edge
        /// alpha mask that starts fading at `visibleOuterFactor` of the
        /// geometric radius.
        public static var visibleOuterRadius: CGFloat {
            haloDiameter / 2 * AppPreferences.visibleOuterFactor
        }
        /// Where each slot icon's centre sits along the donut's radius.
        /// User-tunable; defaults to the midpoint between hub edge and
        /// visible outer rim.
        public static var iconRadius: CGFloat {
            AppPreferences.shared.iconRadius
        }
        /// App icon size inside a sector. User-tunable.
        public static var iconSize: CGFloat {
            AppPreferences.shared.iconSize
        }
        /// Where the curved tooltip label floats outside the wheel.
        /// +36pt (down from +56pt) brings the chip closer so it reads
        /// as part of the slot rather than detached. Still clears the
        /// halo glow (~20pt past rim) and the wheel's drop shadow.
        /// Labels are entirely hidden while the Action Arc is up, so
        /// chip↔label collision in that mode isn't a concern.
        public static var labelRadius: CGFloat {
            haloDiameter / 2 + 36
        }
        public static let labelMaxWidth: CGFloat = 220
        /// Breathing room so the halo glow + label + shadow + Action Arc
        /// chips all fit in the panel without clipping. Sized to hold the
        /// arc's `arcRadius + chip half + label height` at the diagonal
        /// slot positions where the chip extends farthest from centre.
        /// Bumped from +200 → +280 when the arc landed.
        public static var totalDiameter: CGFloat {
            haloDiameter + 280
        }
        /// User-tunable renderer-time scale (Settings → Appearance →
        /// Panel size). Multiplies every layout dimension at draw time so
        /// users can enlarge the whole wheel without re-tuning diameter /
        /// icon size individually.
        public static var panelScale: CGFloat {
            AppPreferences.shared.panelScale
        }
        /// `totalDiameter` post-scale. Used by `HaloWindow` to size the
        /// host NSPanel so the scaled SwiftUI root has somewhere to draw.
        public static var scaledTotalDiameter: CGFloat {
            totalDiameter * panelScale
        }
        /// Gap between adjacent sectors (degrees).
        public static let slotGapDegrees: Double = 1.0
        public static let originAngleDegrees: Double = -90
        /// Where the disc + sector-overlay alpha mask switches from fully
        /// opaque to a linear falloff. Independent from `visibleOuterFactor`
        /// (which anchors slot icons / digit-key hints / Arc geometry, all
        /// of which must stay where the user is used to seeing them) so we
        /// can widen the rim feathering for anti-aliasing without nudging
        /// the wheel's content layout.
        ///
        /// 0.80 (vs. the old 0.84): an 18 %-radius falloff band instead of
        /// 16 % gives the alpha gradient ~12 % gentler slope, which combined
        /// with `LegacyAntialiased` removes the visible "tire tread" rim
        /// stair-stepping in both light and dark mode.
        public static let softEdgeStart: CGFloat = 0.80
    }
}
