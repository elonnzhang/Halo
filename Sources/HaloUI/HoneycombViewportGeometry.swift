import CoreGraphics
import Foundation

/// Geometry of a moving viewport over a fixed honeycomb. Slot assignment is
/// independent of pan and zoom; only the inexpensive projection changes.
public enum HoneycombViewportGeometry {
    public static let baseIconSize: CGFloat = 76
    public static let baseSpacing: CGFloat = 100
    public static let verticalStretch: CGFloat = 1.18

    public struct Layout {
        /// Cell centres relative to the viewport centre at 1× zoom.
        public let offsets: [CGPoint]
        public let bounds: CGRect
    }

    public struct Projection: Equatable {
        public let center: CGPoint
        public let scale: CGFloat
        public let distance: CGFloat

        public func iconFrame(size: CGFloat) -> CGRect {
            let side = size * scale
            return CGRect(x: center.x - side / 2, y: center.y - side / 2,
                          width: side, height: side)
        }
    }

    /// Reserve the profile strip once at canonical zoom, rather than moving
    /// apps into different slots whenever they cross the strip during a pan.
    /// Callers pass the strip in canonical coordinates via `layoutExclusion`
    /// so the reserved hole can be re-anchored once the viewport settles.
    public static func layout(
        count: Int, spacing: CGFloat, iconSize: CGFloat,
        viewSize: CGSize, exclusion: CGRect?
    ) -> Layout {
        let natural = HoneycombGeometry.spiralLayout(count: count)
        let naturalBounds = HoneycombGeometry.layoutBounds(
            layout: natural, spacing: spacing, verticalStretch: verticalStretch)
        let origin = CGPoint(x: viewSize.width / 2 - naturalBounds.midX,
                             y: viewSize.height / 2 - naturalBounds.midY)
        let slots = HoneycombGeometry.adaptiveSpiralLayout(
            count: count, spacing: spacing, verticalStretch: verticalStretch,
            keepOut: exclusion?.insetBy(dx: -iconSize * 0.52, dy: -iconSize * 0.52),
            originX: origin.x, originY: origin.y)
        let offsets = slots.map { slot in
            let point = HoneycombGeometry.center(
                row: slot.row, col: slot.col, spacing: spacing,
                verticalStretch: verticalStretch)
            return CGPoint(x: point.x - naturalBounds.midX,
                           y: point.y - naturalBounds.midY)
        }
        let bounds = HoneycombGeometry.layoutBounds(
            layout: slots, spacing: spacing, verticalStretch: verticalStretch)
            .offsetBy(dx: -naturalBounds.midX, dy: -naturalBounds.midY)
        return Layout(offsets: offsets, bounds: bounds)
    }

    /// Map a fixed on-screen overlay into the canonical (pan 0, zoom 1)
    /// coordinates used by `layout`. Rendering applies
    /// `viewCenter + offset * zoom + pan`; this is its inverse, ignoring
    /// the focus lens, whose residual drift the strip fade already covers.
    public static func layoutExclusion(
        _ rect: CGRect?, viewSize: CGSize, pan: CGSize, zoom: CGFloat
    ) -> CGRect? {
        guard let rect else { return nil }
        let zoom = max(zoom, 0.0001)
        let cx = viewSize.width / 2
        let cy = viewSize.height / 2
        return CGRect(x: cx + (rect.minX - cx - pan.width) / zoom,
                      y: cy + (rect.minY - cy - pan.height) / zoom,
                      width: rect.width / zoom, height: rect.height / zoom)
    }

    /// A smoothstep lens has zero slope at both ends. Icons crossing the
    /// focus radius therefore change size without a visible change of speed.
    public static func project(
        offset: CGPoint, viewCenter: CGPoint, focus: CGPoint,
        pan: CGSize, zoom: CGFloat, radius: CGFloat,
        minimumScale: CGFloat, maximumScale: CGFloat,
        pull: CGFloat = 0.12
    ) -> Projection {
        let flat = CGPoint(x: viewCenter.x + offset.x * zoom + pan.width,
                           y: viewCenter.y + offset.y * zoom + pan.height)
        let dx = flat.x - focus.x
        let dy = flat.y - focus.y
        let distance = hypot(dx, dy)
        let t = radius > 0 ? min(max(distance / radius, 0), 1) : 0
        let eased = t * t * (3 - 2 * t)
        let scale = maximumScale + (minimumScale - maximumScale) * eased
        let contraction = min(max(pull, 0), 0.2) * eased
        return Projection(
            center: CGPoint(x: flat.x - dx * contraction,
                            y: flat.y - dy * contraction),
            scale: scale, distance: distance)
    }

    public static func panLimits(bounds: CGRect, viewSize: CGSize,
                                 zoom: CGFloat, iconSize: CGFloat) -> CGSize {
        // Permit exploration to the last icon, while keeping that icon's
        // centre on screen. Account for an asymmetric reserved-strip layout.
        CGSize(width: max(0, viewSize.width / 2
                          + max(abs(bounds.minX), abs(bounds.maxX)) * zoom - iconSize / 2),
               height: max(0, viewSize.height / 2
                           + max(abs(bounds.minY), abs(bounds.maxY)) * zoom - iconSize / 2))
    }

    public static func clamp(_ pan: CGSize, limits: CGSize) -> CGSize {
        CGSize(width: min(max(pan.width, -limits.width), limits.width),
               height: min(max(pan.height, -limits.height), limits.height))
    }

    /// Closed-form friction: elapsed time, rather than the number of frames,
    /// determines motion. A dropped frame cannot extend or speed up a coast.
    struct Coast {
        let origin: CGSize
        let travel: CGSize
        static let decay: CGFloat = 8

        init(origin: CGSize, predictedTravel: CGSize) {
            self.origin = origin
            let length = hypot(predictedTravel.width, predictedTravel.height)
            let factor = length > 260 ? 260 / length : 1
            travel = CGSize(width: predictedTravel.width * factor,
                            height: predictedTravel.height * factor)
        }

        func value(at elapsed: TimeInterval, limits: CGSize) -> CGSize {
            let fraction = 1 - exp(-Self.decay * max(0, elapsed))
            return HoneycombViewportGeometry.clamp(
                CGSize(width: origin.width + travel.width * fraction,
                       height: origin.height + travel.height * fraction), limits: limits)
        }

        func isFinished(at elapsed: TimeInterval, limits: CGSize) -> Bool {
            let current = value(at: elapsed, limits: limits)
            let target = HoneycombViewportGeometry.clamp(
                CGSize(width: origin.width + travel.width,
                       height: origin.height + travel.height), limits: limits)
            return hypot(target.width - current.width, target.height - current.height) < 0.25
        }
    }

    /// Critically damped spring with explicit starting velocity. Retargeting
    /// a wheel-zoom burst preserves both its visible value and its velocity.
    struct ZoomSpring {
        let origin: CGFloat
        let target: CGFloat
        let velocity: CGFloat
        private let frequency: CGFloat = 24

        func sample(at elapsed: TimeInterval) -> (value: CGFloat, velocity: CGFloat) {
            let t = CGFloat(max(0, elapsed))
            let displacement = origin - target
            let coefficient = velocity + frequency * displacement
            let decay = exp(-frequency * t)
            return (target + (displacement + coefficient * t) * decay,
                    (velocity - frequency * coefficient * t) * decay)
        }

        func isFinished(at elapsed: TimeInterval) -> Bool {
            let sample = sample(at: elapsed)
            return abs(sample.value - target) < 0.0005 && abs(sample.velocity) < 0.005
        }
    }
}
