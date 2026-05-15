import CoreGraphics
import Foundation

/// Pure geometry helpers for the Action Arc. Center-origin, y-up (math
/// convention), to match `RadialGeometry`. Kept side-effect-free so we
/// can unit-test chip hit-testing without spinning up SwiftUI.
public enum ActionArcGeometry {
    /// Distance from wheel centre to a chip centre. +60pt felt too
    /// close to the disc once Halo's drop shadow blended in; +90pt is
    /// the sweet spot — chip clears the wheel cleanly while still
    /// sitting between disc and the profile tab strip above.
    @MainActor
    public static var arcRadius: CGFloat {
        HaloUI.Geometry.visibleOuterRadius + 80
    }
    /// Total angular span of the 4 chips, in degrees.
    public static let arcSpanDegrees: Double = 48
    /// Diameter (≈ hit radius * 2) for each chip.
    public static let chipDiameter: CGFloat = 42
    /// Cursor cushion past the visual chip rim so a cursor "near" the chip
    /// still counts as hover.
    public static let hitPadding: CGFloat = 10

    /// Slot bearing in math convention (12 o'clock = π/2, clockwise).
    public static func slotAngle(slotIndex: Int, sectorCount: Int) -> Double {
        let slice = 2 * .pi / Double(max(sectorCount, 1))
        return .pi / 2 - Double(slotIndex) * slice
    }

    /// Centre of chip `idx` (math-convention coords, y-up). Mirrors
    /// `ActionArcView.chipPosition(at:)`.
    @MainActor
    public static func chipCenter(
        chipIndex: Int,
        slotIndex: Int,
        sectorCount: Int,
        chipCount: Int
    ) -> CGPoint {
        let slot = slotAngle(slotIndex: slotIndex, sectorCount: sectorCount)
        let spanRad = arcSpanDegrees * .pi / 180
        let step = spanRad / Double(max(chipCount - 1, 1))
        // SwiftUI's offset y goes down, but our chipPosition negates sin
        // for that; here we return math-convention y-up for the hit-test
        // helper to consume.
        let start = slot + spanRad / 2
        let a = start - step * Double(chipIndex)
        return CGPoint(x: cos(a) * arcRadius, y: sin(a) * arcRadius)
    }

    /// Closest chip to `point`, or nil if no chip is within hit radius.
    /// Input `point` is in math-convention coordinates relative to the
    /// wheel centre (y-up). HaloWindow's cursor timer already produces
    /// y-up coords (Cocoa's mouse.y is y-up), so no flipping needed —
    /// the previous version flipped y a second time, which made the
    /// comparison miss for every slot except those where chip y ≈ 0.
    ///
    /// We compare squared distances against `(chipDiameter/2 + hitPadding)^2`
    /// so the user can "approach" a chip without pixel-perfect aiming.
    @MainActor
    public static func chipIndex(
        forCenteredPoint point: CGPoint,
        slotIndex: Int,
        sectorCount: Int,
        chipCount: Int
    ) -> Int? {
        let hitR = chipDiameter / 2 + hitPadding
        let hitR2 = hitR * hitR
        var best: (idx: Int, d2: CGFloat)?
        for i in 0..<chipCount {
            let c = chipCenter(
                chipIndex: i,
                slotIndex: slotIndex,
                sectorCount: sectorCount,
                chipCount: chipCount
            )
            let dx = c.x - point.x
            let dy = c.y - point.y
            let d2 = dx * dx + dy * dy
            guard d2 <= hitR2 else { continue }
            if best == nil || d2 < best!.d2 { best = (i, d2) }
        }
        return best?.idx
    }
}
