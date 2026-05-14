import CoreGraphics
import Foundation
import SwiftUI

/// Pie-slice shape for a single sector. Drawn into the wheel's outer circle —
/// the donut hole is provided by the centerHub overlay rendered on top.
///
/// Sector `i` is centered on `i * slice` clockwise from 12 o'clock, so its
/// wedge starts half a slice before that. Outer ring is inset inward by the
/// stroke width so neighbouring sectors don't visually overlap.
public struct SectorShape: Shape {
    public let index: Int
    public let sectorCount: Int
    public let gapDegrees: Double

    public init(index: Int, sectorCount: Int, gapDegrees: Double = 1.0) {
        self.index = index
        self.sectorCount = sectorCount
        self.gapDegrees = gapDegrees
    }

    public func path(in rect: CGRect) -> Path {
        guard sectorCount > 0 else { return Path() }

        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let slice = 360.0 / Double(sectorCount)
        let halfGap = gapDegrees / 2

        // "0 at top, clockwise" → convert to SwiftUI's Angle (0° at 3 o'clock,
        // CCW) by shifting -90°.
        let startDeg = -90 + Double(index) * slice - slice / 2 + halfGap
        let endDeg   = -90 + Double(index) * slice + slice / 2 - halfGap

        let arcStart = Angle(degrees: startDeg)
        let arcEnd   = Angle(degrees: endDeg)

        var path = Path()
        path.move(to: center)
        let startPoint = CGPoint(
            x: center.x + cos(arcStart.radians) * radius,
            y: center.y + sin(arcStart.radians) * radius
        )
        path.addLine(to: startPoint)
        path.addArc(
            center: center,
            radius: radius,
            startAngle: arcStart,
            endAngle: arcEnd,
            clockwise: false
        )
        path.closeSubpath()
        return path
    }
}

/// A partial arc on the unit circle, used for liquid-glass specular
/// highlights. Angles are degrees in SwiftUI's native convention (0° at
/// 3 o'clock, clockwise). For a 12 o'clock highlight centered on "up" pass
/// `-135° … -45°` (90° wide, symmetric around -90°).
public struct SpecularArc: Shape {
    public let startAngleDegrees: Double
    public let endAngleDegrees: Double

    public init(startAngleDegrees: Double, endAngleDegrees: Double) {
        self.startAngleDegrees = startAngleDegrees
        self.endAngleDegrees = endAngleDegrees
    }

    public func path(in rect: CGRect) -> Path {
        var path = Path()
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        path.addArc(
            center: center,
            radius: radius,
            startAngle: .degrees(startAngleDegrees),
            endAngle: .degrees(endAngleDegrees),
            clockwise: false
        )
        return path
    }
}

/// Pure geometry helpers for the radial wheel. Center-origin, y-up.
public enum RadialGeometry {
    /// Returns the index of the sector that contains `point` (origin at wheel
    /// center, y pointing up). Points inside `innerRadius` or outside
    /// `outerRadius` return nil so the hub and outside area are inert.
    public static func sectorIndex(
        for point: CGPoint,
        sectorCount: Int,
        innerRadius: CGFloat,
        outerRadius: CGFloat
    ) -> Int? {
        guard sectorCount > 0 else { return nil }

        let distance = hypot(point.x, point.y)
        guard distance >= innerRadius, distance <= outerRadius else { return nil }

        // atan2 returns (-π, π] with 0 at 3 o'clock CCW. Convert to
        // "0 at 12 o'clock, clockwise" then shift by half a slice so each
        // sector is centered on its cardinal angle.
        let slice = 2 * .pi / Double(sectorCount)
        var theta = .pi / 2 - atan2(Double(point.y), Double(point.x)) + slice / 2
        theta = theta.truncatingRemainder(dividingBy: 2 * .pi)
        if theta < 0 { theta += 2 * .pi }

        return Int(floor(theta / slice)) % sectorCount
    }

    /// Variant for callers that receive a gesture location in **scaled**
    /// view coordinates (post-`scaleEffect(panelScale)`) and need to
    /// hit-test against the **unscaled** geometry. Mirrors the cursor
    /// timer path in `HaloWindow.updateHoverFromCursor`. Returns the
    /// same nil semantics (deadzone / outside rim) as
    /// `sectorIndex(for:sectorCount:innerRadius:outerRadius:)`.
    ///
    /// Bug history: before this helper existed, `RadialView.sectorIndex`
    /// fed `value.location` (scaled) straight into the unscaled math,
    /// so any non-1.0 `panelScale` shifted hit-tests by a factor of
    /// `panelScale`. On a 1.3x panel a click on slot 0 hit-tested to
    /// slot 1, briefly flashing the next slot before commit.
    public static func sectorIndex(
        forGestureLocation location: CGPoint,
        panelScale: CGFloat,
        totalDiameter: CGFloat,
        sectorCount: Int,
        innerRadius: CGFloat,
        outerRadius: CGFloat
    ) -> Int? {
        // Belt and braces — `AppPreferences.panelScale` is already
        // clamped to [0.80, 1.50] on write so this clamp is a defensive
        // guard against future callers or test inputs.
        let scale = max(panelScale, 0.001)
        let x = location.x / scale
        let y = location.y / scale
        let centered = CGPoint(
            x: x - totalDiameter / 2,
            y: totalDiameter / 2 - y
        )
        return sectorIndex(
            for: centered,
            sectorCount: sectorCount,
            innerRadius: innerRadius,
            outerRadius: outerRadius
        )
    }

    /// Center point of a sector at a given radius (y-up, center-origin).
    /// Sector 0 is at 12 o'clock; subsequent sectors advance clockwise.
    public static func center(of sectorIndex: Int, sectorCount: Int, radius: CGFloat) -> CGPoint {
        let slice = 2 * .pi / Double(max(sectorCount, 1))
        let angle = .pi / 2 - Double(sectorIndex) * slice
        return CGPoint(x: cos(angle) * Double(radius), y: sin(angle) * Double(radius))
    }
}

/// Pure geometry for clamping the wheel to the screen when summoned at the
/// cursor. When the cursor is too close to an edge, the wheel is pushed inward
/// by exactly the overflow distance; when the screen can't fit the wheel, the
/// wheel is centered on the visible frame (degenerate fallback).
public enum RadialPanelFrame {
    public static func frame(
        forCursor cursor: CGPoint,
        in visibleFrame: CGRect,
        wheelSize: CGFloat
    ) -> CGRect {
        let size = CGSize(width: wheelSize, height: wheelSize)
        if visibleFrame.width < wheelSize || visibleFrame.height < wheelSize {
            return CGRect(
                origin: CGPoint(
                    x: visibleFrame.midX - wheelSize / 2,
                    y: visibleFrame.midY - wheelSize / 2
                ),
                size: size
            )
        }
        let desiredX = cursor.x - wheelSize / 2
        let desiredY = cursor.y - wheelSize / 2
        let minX = visibleFrame.minX
        let maxX = visibleFrame.maxX - wheelSize
        let minY = visibleFrame.minY
        let maxY = visibleFrame.maxY - wheelSize
        let clampedX = max(minX, min(desiredX, maxX))
        let clampedY = max(minY, min(desiredY, maxY))
        return CGRect(origin: CGPoint(x: clampedX, y: clampedY), size: size)
    }
}
