import Foundation
import HaloCore

public enum HaloUI {
    public static let version = Halo.version

    /// Radial wheel layout — outer ring, inner hub, where icons sit, where the
    /// curved tooltip floats. Kept in one place so geometry + hit-testing +
    /// panel sizing can't drift.
    public enum Geometry {
        /// Outer donut diameter.
        public static let hudDiameter: CGFloat = 320
        /// Center hub (deadzone) diameter. Hit-tests inside are inert.
        public static let deadzoneDiameter: CGFloat = 112
        /// Where each slot icon's center sits along the donut's radius.
        public static let iconRadius: CGFloat = (hudDiameter + deadzoneDiameter) / 4
        /// App icon size inside a sector.
        public static let iconSize: CGFloat = 48
        /// Where the curved tooltip label floats outside the wheel.
        public static let labelRadius: CGFloat = hudDiameter / 2 + 28
        public static let labelMaxWidth: CGFloat = 220
        /// Breathing room so the halo glow + label + shadow all fit in the
        /// panel without clipping.
        public static let totalDiameter: CGFloat = hudDiameter + 120
        /// Gap between adjacent sectors (degrees).
        public static let slotGapDegrees: Double = 1.0
        public static let originAngleDegrees: Double = -90
    }
}
