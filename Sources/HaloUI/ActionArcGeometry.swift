import CoreGraphics
import Foundation

/// Pure geometry helpers for the Action Arc. Center-origin, y-up (math
/// convention), to match `RadialGeometry`. Kept side-effect-free so we
/// can unit-test chip hit-testing without spinning up SwiftUI.
public enum ActionArcGeometry {
    /// Distance from wheel centre to a chip centre. Matches the constant
    /// in `ActionArcView`.
    public static let arcRadius: CGFloat = 240
    /// Total angular span of the 4 chips, in degrees.
    public static let arcSpanDegrees: Double = 48
    /// Diameter (≈ hit radius * 2) for each chip.
    public static let chipDiameter: CGFloat = 42
    /// Cursor cushion past the visual chip rim so a cursor "near" the chip
    /// still counts as hover.
    public static let hitPadding: CGFloat = 8

    /// Slot bearing in math convention (12 o'clock = π/2, clockwise).
    public static func slotAngle(slotIndex: Int, sectorCount: Int) -> Double {
        let slice = 2 * .pi / Double(max(sectorCount, 1))
        return .pi / 2 - Double(slotIndex) * slice
    }

    /// Centre of chip `idx` (math-convention coords, y-up). Mirrors
    /// `ActionArcView.chipPosition(at:)`.
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
    /// wheel centre. (HaloWindow's cursor timer feeds y in math
    /// convention by mapping the SwiftUI-flipped y back; see HaloWindow.)
    ///
    /// We compare squared distances against `(chipDiameter/2 + hitPadding)^2`
    /// so the user can "approach" a chip without pixel-perfect aiming.
    public static func chipIndex(
        forCenteredPoint point: CGPoint,
        slotIndex: Int,
        sectorCount: Int,
        chipCount: Int
    ) -> Int? {
        // The cursor timer hands us y in SwiftUI convention (y-down). We
        // convert here once so callers don't have to think about it.
        let p = CGPoint(x: point.x, y: -point.y)
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
            let dx = c.x - p.x
            let dy = c.y - p.y
            let d2 = dx * dx + dy * dy
            guard d2 <= hitR2 else { continue }
            if best == nil || d2 < best!.d2 { best = (i, d2) }
        }
        return best?.idx
    }
}
