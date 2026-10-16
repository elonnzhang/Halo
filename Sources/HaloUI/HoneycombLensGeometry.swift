import CoreGraphics
import Foundation

/// Pure geometry for the ALL lens honeycomb, adapted from onevra's
/// `source/components/honeycomb.go` (MIT, (c) 2026 ONEO). Unlike the earlier
/// constellation, which pans a flat sheet under a fixed lens, this pans a
/// point of the honeycomb into the middle of the view: items shrink with
/// their distance from it, sit on the surface of a ball, and fade at the edge.
public enum HoneycombLensGeometry {
    /// How much of the pointer's travel moves the honeycomb past its edge.
    public static let rubber: CGFloat = 0.35
    /// How long a released drag goes on at its speed before settling.
    public static let inertia: CGFloat = 0.3
    /// Pointer travel below which a release is a click.
    public static let tapSlop: CGFloat = 4
    public static let glideDuration: TimeInterval = 0.42
    /// Scrolling must stop this long before the honeycomb settles.
    public static let settleDelay: TimeInterval = 0.15
    /// Default degrees an item turns away from the viewer at the far edge.
    /// onevra uses 60; a gentler ball reads better at full-screen icon sizes.
    /// Users tune it in Settings → General → Appearance.
    public static let maxTilt: CGFloat = 27
    /// Upper bound on the lens's horizontal stretch, so an ultrawide display
    /// does not flatten the middle into a band.
    public static let maxStretch: CGFloat = 2.2

    public struct Metrics: Equatable {
        public let large, small, tiny, fall, tiltFall, spacing, ring, edge: CGFloat
        /// Per-axis stretch of the lens. A screen is wider than tall, so the
        /// lens is an ellipse of the screen's proportions rather than a
        /// circle: (1, 1) is onevra's round lens.
        public var stretch = CGSize(width: 1, height: 1)
        /// Degrees of tilt at the far edge.
        public var maxTilt = HoneycombLensGeometry.maxTilt

        /// onevra's design lengths, scaled by `s`. `ratio` nil follows the
        /// view's aspect ratio; otherwise it stretches the view's long axis.
        public static func scaled(_ s: CGFloat, viewSize: CGSize = .zero,
                                  ratio: CGFloat? = nil,
                                  maxTilt: CGFloat = HoneycombLensGeometry.maxTilt) -> Metrics {
            var m = Metrics(large: 84 * s, small: 56 * s, tiny: 14 * s, fall: 150 * s,
                            tiltFall: 420 * s, spacing: 66 * s, ring: 2 * s, edge: 66 * s)
            m.stretch = HoneycombLensGeometry.stretch(for: viewSize, ratio: ratio)
            m.maxTilt = min(max(maxTilt, 0), 89)
            return m
        }

        /// Elliptical distance: the long axis counts for less, so sizes and
        /// spacing fall off over the screen's width and height alike.
        public func distance(_ dx: CGFloat, _ dy: CGFloat) -> CGFloat {
            hypot(dx / stretch.width, dy / stretch.height)
        }

        /// Pointer travel maps to this much honeycomb travel, so the
        /// magnified middle follows the pointer one-to-one.
        public var panRatio: CGFloat { small / large }

        /// Item size `d` (unmagnified) from the middle of the view.
        public func size(_ d: CGFloat) -> CGFloat {
            tiny + (large - tiny) * exp(-d / fall)
        }

        public func tilt(_ d: CGFloat) -> CGFloat {
            maxTilt * (1 - exp(-d / tiltFall))
        }

        /// Drawn distance from the middle of a point `d` from it: the
        /// integral of `size`, so spacing shrinks with the items.
        public func magnified(_ d: CGFloat) -> CGFloat {
            (tiny * d + (large - tiny) * fall * (1 - exp(-d / fall))) / small
        }
    }

    public struct Placement: Equatable {
        public let center: CGPoint
        public let size: CGFloat
        public let opacity: CGFloat
        /// Radial direction, used to squash the item along it.
        public let angle: CGFloat
        /// `cos(tilt)`: 1 faces the viewer.
        public let squash: CGFloat
        public let distance: CGFloat
    }

    /// Stretch the short axis 1 and the long axis the view's aspect ratio,
    /// or `ratio` when given.
    public static func stretch(for viewSize: CGSize, ratio: CGFloat? = nil) -> CGSize {
        guard viewSize.width > 0, viewSize.height > 0 else { return CGSize(width: 1, height: 1) }
        let aspect = viewSize.width / viewSize.height
        let long = min(max(ratio ?? max(aspect, 1 / aspect), 1), maxStretch)
        return aspect >= 1 ? CGSize(width: long, height: 1) : CGSize(width: 1, height: long)
    }

    /// Cell centres, filling outward from the first in an ellipse of the
    /// lens's proportions, so the honeycomb's outline matches the screen.
    public static func cells(count: Int, spacing: CGFloat,
                             stretch: CGSize = CGSize(width: 1, height: 1)) -> [CGPoint] {
        guard count > 0 else { return [] }
        let sx = max(stretch.width, 0.01), sy = max(stretch.height, 0.01)
        // Rings until the inscribed ellipse holds `count` cells with room.
        let rows = Int(ceil(sqrt(Double(count) / (Double(sx * sy) * 0.9)) * Double(sy))) + 2
        let cols = Int(ceil(Double(rows) * Double(sx / sy))) + 2
        var candidates: [(point: CGPoint, distance: CGFloat, angle: CGFloat)] = []
        candidates.reserveCapacity((2 * rows + 1) * (2 * cols + 1))
        for row in -rows...rows {
            for col in -cols...cols {
                let p = HoneycombGeometry.center(row: row, col: col, spacing: spacing)
                var angle = atan2(p.y, p.x)
                if angle < 0 { angle += 2 * .pi }
                candidates.append((p, hypot(p.x / sx, p.y / sy), angle))
            }
        }
        candidates.sort {
            abs($0.distance - $1.distance) > 0.0001 ? $0.distance < $1.distance : $0.angle < $1.angle
        }
        return candidates.prefix(count).map(\.point)
    }

    public static func bounds(of cells: [CGPoint]) -> CGRect {
        guard let first = cells.first else { return .zero }
        var minX = first.x, maxX = first.x, minY = first.y, maxY = first.y
        for p in cells {
            minX = min(minX, p.x); maxX = max(maxX, p.x)
            minY = min(minY, p.y); maxY = max(maxY, p.y)
        }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    public static func nearest(in cells: [CGPoint], to point: CGPoint) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for (i, c) in cells.enumerated() {
            let d = hypot(c.x - point.x, c.y - point.y)
            if best == nil || d < best!.distance { best = (i, d) }
        }
        return best?.index
    }

    /// Move the middle point by `delta`, at `rubber` of the speed while
    /// moving further past the honeycomb's bounds.
    public static func pan(_ at: CGPoint, by delta: CGSize, within bounds: CGRect) -> CGPoint {
        func past(_ v: CGFloat, _ lo: CGFloat, _ hi: CGFloat, _ d: CGFloat) -> CGFloat {
            (v < lo && d < 0) || (v > hi && d > 0) ? d * rubber : d
        }
        return CGPoint(x: at.x + past(at.x, bounds.minX, bounds.maxX, delta.width),
                       y: at.y + past(at.y, bounds.minY, bounds.maxY, delta.height))
    }

    /// Spare cells beyond the app count, so apps displaced from under the
    /// profile strip have somewhere to go.
    public static let spareCells = 64

    /// Where the lens middle is drawn: the view centre, unless the profile
    /// strip covers it, in which case just clear of the strip so the focal
    /// app is never hidden under it.
    public static func lensCentre(viewSize: CGSize, strip: CGRect?, clearance: CGFloat) -> CGPoint {
        let c = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        guard let strip else { return c }
        let zone = strip.insetBy(dx: -clearance, dy: -clearance)
        guard zone.contains(c) else { return c }
        return CGPoint(x: c.x, y: strip.midY <= c.y ? zone.maxY : zone.minY)
    }

    /// Slots whose rendered icon, for the lens middle at `at`, would touch
    /// the profile strip.
    public static func blockedSlots(_ slots: [CGPoint], at: CGPoint, viewSize: CGSize,
                                    centre: CGPoint, metrics: Metrics, strip: CGRect?,
                                    margin: CGFloat = 4) -> Set<Int> {
        guard let strip, viewSize.width > 0, viewSize.height > 0 else { return [] }
        var blocked = Set<Int>()
        for (j, slot) in slots.enumerated() {
            let p = place(cell: slot, at: at, viewSize: viewSize, metrics: metrics, centre: centre)
            let reach = p.size / 2 + margin
            if strip.insetBy(dx: -reach, dy: -reach).contains(p.center) { blocked.insert(j) }
        }
        return blocked
    }

    /// App `i` keeps slot `i` unless it is blocked; blocked apps take the
    /// nearest free slot, in spiral order so the result is deterministic.
    /// Returns one slot index per app.
    public static func assign(count: Int, slots: [CGPoint], blocked: Set<Int>,
                              metrics: Metrics) -> [Int] {
        let n = min(count, slots.count)
        guard !blocked.isEmpty else { return Array(0..<n) }
        var picked = [Int?](repeating: nil, count: n)
        var used = Set<Int>()
        for i in 0..<n where !blocked.contains(i) {
            picked[i] = i
            used.insert(i)
        }
        for i in 0..<n where picked[i] == nil {
            var best: (slot: Int, distance: CGFloat)?
            for j in slots.indices where !used.contains(j) && !blocked.contains(j) {
                let d = metrics.distance(slots[j].x - slots[i].x, slots[j].y - slots[i].y)
                if best == nil || d < best!.distance { best = (j, d) }
            }
            // No free slot left: stay put under the strip rather than vanish.
            let slot = best?.slot ?? i
            picked[i] = slot
            used.insert(slot)
        }
        return picked.map { $0! }
    }

    public static func place(cell: CGPoint, at: CGPoint, viewSize: CGSize,
                             metrics m: Metrics, centre: CGPoint? = nil) -> Placement {
        let dx = cell.x - at.x
        let dy = cell.y - at.y
        let d = m.distance(dx, dy)
        var cx = centre?.x ?? viewSize.width / 2
        var cy = centre?.y ?? viewSize.height / 2
        if d > 0 {
            let f = m.magnified(d) / d
            cx += dx * f
            cy += dy * f
        }
        // Distance into the edge inset, rounded at the corners as on a watch.
        let edge = min(m.edge, viewSize.width / 2, viewSize.height / 2)
        let ox = max(edge - cx, cx - viewSize.width + edge, 0)
        let oy = max(edge - cy, cy - viewSize.height + edge, 0)
        let out = min(hypot(ox, oy) / max(edge, 1), 1)
        let size = m.tiny + (m.size(d) - m.tiny) * (1 - out)
        let tilt = d > 0 ? m.tilt(d) : 0
        // An ellipsoid slopes along the gradient of the elliptical distance.
        let sx = m.stretch.width, sy = m.stretch.height
        return Placement(center: CGPoint(x: cx, y: cy), size: size,
                         opacity: 1 - ramp(out, from: 0.35, to: 0.85),
                         angle: atan2(dy / (sy * sy), dx / (sx * sx)),
                         squash: cos(tilt * .pi / 180), distance: d)
    }

    /// The round item drawn under `point`, nearest its centre if several are.
    /// Nearly transparent edge items are not clickable.
    public static func hit(_ placements: [(index: Int, placement: Placement)],
                           at point: CGPoint) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for (index, p) in placements where p.opacity > 0.15 {
            let d = hypot(point.x - p.center.x, point.y - p.center.y)
            if d <= p.size / 2, best == nil || d < best!.distance { best = (index, d) }
        }
        return best?.index
    }

    public static func ramp(_ v: CGFloat, from: CGFloat, to: CGFloat) -> CGFloat {
        let t = min(max((v - from) / (to - from), 0), 1)
        return t * t * (3 - 2 * t)
    }

    public static func easeInOut(_ t: CGFloat) -> CGFloat {
        let t = min(max(t, 0), 1)
        return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
    }
}
