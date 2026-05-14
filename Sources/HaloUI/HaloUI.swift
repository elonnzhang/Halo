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
        /// Where the curved tooltip label floats outside the wheel. Pushed
        /// far enough out that the chip never lands on the wheel's halo glow
        /// (which extends ~20pt past the disc rim) or shadow.
        public static var labelRadius: CGFloat {
            haloDiameter / 2 + 56
        }
        public static let labelMaxWidth: CGFloat = 220
        /// Breathing room so the halo glow + label + shadow all fit in the
        /// panel without clipping. Sized to contain a max-width label at the
        /// diagonal slot positions (45°, 135°, …) where the chip extends
        /// farthest from centre.
        public static var totalDiameter: CGFloat {
            haloDiameter + 200
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
    }
}
