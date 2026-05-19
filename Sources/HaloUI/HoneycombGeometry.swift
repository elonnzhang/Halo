import CoreGraphics
import Foundation

/// Pure-math helpers for the watchOS-style honeycomb grid.
///
/// Kept stateless and free of SwiftUI / AppKit so the math is unit-testable
/// without any rendering harness. Rendering lives in `HoneycombGridView`,
/// which composes these functions inside a `GeometryReader`.
public enum HoneycombGeometry {
    /// Centre of the cell at (`row`, `col`) in an offset honeycomb. Even
    /// rows align with the grid's x origin; odd rows are shifted right
    /// by `spacing / 2` so adjacent rows interlock. Vertical pitch is
    /// `spacing * sin(60°)` ≈ `spacing * 0.866` which yields a regular
    /// hexagonal lattice (every cell has 6 equidistant neighbours).
    ///
    /// `row`/`col` may be negative — the math is uniform across the
    /// plane, so callers can centre the grid by feeding signed indices.
    public static func center(
        row: Int,
        col: Int,
        spacing: CGFloat,
        verticalStretch: CGFloat = 1
    ) -> CGPoint {
        let xShift: CGFloat = row.isMultiple(of: 2) ? 0 : spacing / 2
        let x = CGFloat(col) * spacing + xShift
        let y = CGFloat(row) * spacing * 0.866_025_4 * verticalStretch   // sin(60°)
        return CGPoint(x: x, y: y)
    }

    public static func labelAwareCenter(row: Int, col: Int, spacing: CGFloat) -> CGPoint {
        center(row: row, col: col, spacing: spacing, verticalStretch: 1.18)
    }

    /// Fisheye scale factor for an icon at `distance` from the focal
    /// centre. Returns 1.0 at the centre, falling off toward `minScale`
    /// as `distance` approaches `maxRadius`. Beyond `maxRadius` the
    /// scale is clamped at `minScale` so off-screen cells don't
    /// continue shrinking arbitrarily.
    ///
    /// `curve` shapes the falloff: 1.0 is linear; values > 1 keep more
    /// of the centre at full size and bunch the shrink near the rim
    /// (1.8 ≈ watchOS feel); values < 1 do the inverse.
    public static func fisheyeScale(
        distance: CGFloat,
        maxRadius: CGFloat,
        minScale: CGFloat = 0.4,
        curve: CGFloat = 1.8
    ) -> CGFloat {
        guard maxRadius > 0 else { return 1 }
        let t = max(0, min(distance / maxRadius, 1))
        let shaped = pow(t, curve)
        return 1 - (1 - minScale) * shaped
    }

    /// How far an icon should be pushed toward the focal centre to
    /// give the spherical-projection look (icons near the rim drift
    /// inward, not just shrink). Returns the offset to ADD to the
    /// icon's flat-grid position.
    ///
    /// `strength` is the fraction of the radial distance to bias
    /// inward at the rim. 0 disables the projection (pure scale-only
    /// fisheye); 0.15 ≈ watchOS feel.
    public static func fisheyeOffset(
        position: CGPoint,
        viewCenter: CGPoint,
        maxRadius: CGFloat,
        strength: CGFloat = 0.15
    ) -> CGSize {
        guard maxRadius > 0, strength > 0 else { return .zero }
        let dx = position.x - viewCenter.x
        let dy = position.y - viewCenter.y
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance > 0.001 else { return .zero }
        let t = min(distance / maxRadius, 1)
        // Smooth easing — quadratic so points near the centre are
        // barely nudged, points near the rim get the full pull.
        let pull = strength * t * t
        return CGSize(width: -dx * pull, height: -dy * pull)
    }

    /// Pull a search result toward a compact centre constellation while
    /// preserving enough per-index spread that multiple matches remain
    /// individually clickable. `strength` is clamped to 0...1.
    public static func searchAttractedPosition(
        flatPosition: CGPoint,
        viewCenter: CGPoint,
        index: Int,
        strength: CGFloat
    ) -> CGPoint {
        let clamped = max(0, min(strength, 1))
        guard clamped > 0 else { return flatPosition }
        let ring = CGFloat(index % 10)
        let angle = ring / 10 * .pi * 2
        let lane = CGFloat(index / 10) * 18
        let target = CGPoint(
            x: viewCenter.x + cos(angle) * (42 + lane),
            y: viewCenter.y + sin(angle) * (34 + lane)
        )
        return CGPoint(
            x: flatPosition.x + (target.x - flatPosition.x) * clamped,
            y: flatPosition.y + (target.y - flatPosition.y) * clamped
        )
    }

    /// Pull non-committing cells toward the clicked app during launch
    /// collapse. The pull is intentionally short so the selected app
    /// remains the visual anchor while the constellation exits.
    public static func commitCollapseOffset(
        position: CGPoint,
        anchor: CGPoint,
        maxDistance: CGFloat,
        strength: CGFloat
    ) -> CGSize {
        guard maxDistance > 0, strength > 0 else { return .zero }
        let dx = anchor.x - position.x
        let dy = anchor.y - position.y
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance > 0.001 else { return .zero }
        let falloff = max(0, 1 - min(distance / maxDistance, 1))
        let pull = min(28, distance * strength * (0.35 + 0.65 * falloff))
        return CGSize(width: dx / distance * pull, height: dy / distance * pull)
    }

    /// Push neighbours a few points away from a hovered icon, giving the
    /// local magnetic bump of watchOS Home Screen without reflowing the grid.
    public static func hoverRepelOffset(
        position: CGPoint,
        hoverCenter: CGPoint,
        radius: CGFloat,
        strength: CGFloat
    ) -> CGSize {
        guard radius > 0, strength > 0 else { return .zero }
        let dx = position.x - hoverCenter.x
        let dy = position.y - hoverCenter.y
        let distance = (dx * dx + dy * dy).squareRoot()
        guard distance > 0.001, distance < radius else { return .zero }
        let falloff = pow(1 - distance / radius, 2)
        let push = strength * falloff
        return CGSize(width: dx / distance * push, height: dy / distance * push)
    }

    /// Move a cell around a fixed overlay with a soft capsule-shaped
    /// repulsion field. This avoids the hard rectangular cut that would
    /// make icons line up against the ProfileTabBar edge. Points inside
    /// the protected capsule are pushed outside; nearby points get a
    /// smaller falloff push so the honeycomb bends instead of snapping.
    public static func displacedPosition(
        _ position: CGPoint,
        outOf exclusion: CGRect,
        padding: CGFloat = 0,
        verticalBias: CGFloat = 1
    ) -> CGPoint {
        let protected = exclusion.insetBy(dx: -padding, dy: -padding)
        let influence = protected.insetBy(dx: -padding * 2.5, dy: -padding * 2.2)
        let center = CGPoint(x: protected.midX, y: protected.midY)
        let protectedRX = max(protected.width / 2, 1)
        let protectedRY = max(protected.height / 2, 1)
        let influenceRX = max(influence.width / 2, protectedRX + 1)
        let influenceRY = max(influence.height / 2, protectedRY + 1)

        let dx = position.x - center.x
        let dy = position.y - center.y
        let influenceDistance = ((dx / influenceRX) * (dx / influenceRX)
            + (dy / influenceRY) * (dy / influenceRY)).squareRoot()
        guard influenceDistance < 1 else { return position }

        let protectedDistance = ((dx / protectedRX) * (dx / protectedRX)
            + (dy / protectedRY) * (dy / protectedRY)).squareRoot()
        let vx = dx / protectedRX
        let vy = dy / protectedRY
        let vectorLength = max((vx * vx + vy * vy).squareRoot(), 0.001)
        let ux = vx / vectorLength
        let uy = vy / vectorLength
        let boundaryX = center.x + ux * protectedRX
        let boundaryY = center.y + uy * protectedRY
        let requiredX = boundaryX - position.x
        let requiredY = boundaryY - position.y
        let falloff = pow(max(0, 1 - influenceDistance), 2.35)
        let softPush = padding * 0.56 * falloff
        let side: CGFloat = dx == 0 ? 1 : (dx > 0 ? 1 : -1)
        let verticalSide: CGFloat = dy == 0 ? -1 : (dy > 0 ? 1 : -1)
        let tangentBias = padding * 0.20 * falloff * side
        let verticalPush = padding * 0.52 * falloff * verticalBias * verticalSide
        let rawX: CGFloat
        let rawY: CGFloat
        if protectedDistance < 1 {
            rawX = requiredX + ux * softPush + tangentBias
            rawY = requiredY + uy * softPush + verticalPush
        } else {
            rawX = ux * softPush + tangentBias
            rawY = uy * softPush + verticalPush
        }
        let maxPush = min(max(padding * 1.85, 42), 96)
        let length = max((rawX * rawX + rawY * rawY).squareRoot(), 0.001)
        let clamp = min(1, maxPush / length)
        return CGPoint(x: position.x + rawX * clamp,
                       y: position.y + rawY * clamp)
    }

    /// Final collision guard for rendered cells. Unlike the soft field
    /// above, this is a hard constraint: if a cell's visible footprint
    /// would intersect the fixed overlay, move its centre just outside
    /// the inflated rect. Callers should apply this after any fisheye /
    /// hover projection because those effects can move a previously safe
    /// centre back over the overlay.
    public static func resolvedCenter(
        _ center: CGPoint,
        avoiding exclusion: CGRect,
        footprint: CGSize,
        margin: CGFloat = 0
    ) -> CGPoint {
        let avoid = exclusion.insetBy(
            dx: -(footprint.width / 2 + margin),
            dy: -(footprint.height / 2 + margin)
        )
        guard avoid.contains(center) else { return center }

        // Push slightly past the boundary, not exactly onto it. A point
        // sitting on `avoid.minX` makes `visible.intersects(exclusion +
        // margin)` true because CGRect.intersects counts edge-touch as
        // intersecting. The 0.5pt epsilon also leaves headroom for the
        // 0.25-pt convergence threshold in `resolvedProjectedCenter`'s
        // fisheye iteration loop, so post-resolution drift can't pull
        // the cell back onto the boundary. Sub-pixel, visually invisible.
        let eps: CGFloat = 0.5
        let distances: [(point: CGPoint, distance: CGFloat, vertical: Bool)] = [
            (CGPoint(x: avoid.minX - eps, y: center.y), center.x - avoid.minX, false),
            (CGPoint(x: avoid.maxX + eps, y: center.y), avoid.maxX - center.x, false),
            (CGPoint(x: center.x, y: avoid.minY - eps), center.y - avoid.minY, true),
            (CGPoint(x: center.x, y: avoid.maxY + eps), avoid.maxY - center.y, true),
        ]
        guard let best = distances.min(by: { lhs, rhs in
            let lhsScore = lhs.distance * (lhs.vertical ? 0.78 : 1)
            let rhsScore = rhs.distance * (rhs.vertical ? 0.78 : 1)
            return lhsScore < rhsScore
        }) else {
            return center
        }
        return best.point
    }

    /// Resolve a base centre when the renderer applies a second projection
    /// later. This closes the loop that a single `resolvedCenter` call cannot:
    /// moving the base cell changes its projected centre, and that new
    /// projection can otherwise drift back into the fixed overlay.
    public static func resolvedProjectedCenter(
        _ baseCenter: CGPoint,
        projectedCenter: (CGPoint) -> CGPoint,
        footprint: (CGPoint) -> CGSize,
        avoiding exclusion: CGRect,
        margin: CGFloat = 0,
        iterations: Int = 8
    ) -> CGPoint {
        var base = baseCenter
        let maxIterations = max(iterations, 1)
        for _ in 0..<maxIterations {
            let rendered = projectedCenter(base)
            let safe = resolvedCenter(
                rendered,
                avoiding: exclusion,
                footprint: footprint(base),
                margin: margin
            )
            let dx = safe.x - rendered.x
            let dy = safe.y - rendered.y
            if abs(dx) < 0.25, abs(dy) < 0.25 { break }
            base = CGPoint(x: base.x + dx, y: base.y + dy)
        }
        return base
    }

    public static func layoutBounds(
        layout: [(row: Int, col: Int)],
        spacing: CGFloat,
        verticalStretch: CGFloat = 1
    ) -> CGRect {
        guard !layout.isEmpty else { return .zero }
        let points = layout.map {
            center(row: $0.row, col: $0.col, spacing: spacing, verticalStretch: verticalStretch)
        }
        let xs = points.map(\.x)
        let ys = points.map(\.y)
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max()
        else { return .zero }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    /// Layout indices from the centre outward in a pointy honeycomb field.
    /// Index 0 is the visual centre; later indices are sorted by their actual
    /// rendered distance from that centre. This mirrors watchOS Grid View
    /// better than row-major placement because high-priority apps can occupy
    /// the centre and lower-priority apps fall naturally toward smaller outer
    /// rings.
    public static func spiralLayout(count: Int) -> [(row: Int, col: Int)] {
        guard count > 0 else { return [] }
        let radius = max(2, Int(ceil(sqrt(Double(count)))) + 2)
        let candidates = (-radius...radius).flatMap { row in
            (-radius...radius).map { col -> (row: Int, col: Int, distance: CGFloat, angle: CGFloat) in
                let point = center(row: row, col: col, spacing: 1)
                return (
                    row: row,
                    col: col,
                    distance: hypot(point.x, point.y),
                    angle: atan2(point.y, point.x)
                )
            }
        }

        return candidates
            .sorted { lhs, rhs in
                if abs(lhs.distance - rhs.distance) > 0.0001 {
                    return lhs.distance < rhs.distance
                }
                return lhs.angle < rhs.angle
            }
            .prefix(count)
            .map { (row: $0.row, col: $0.col) }
    }

    /// Soft-fade alpha for cells that drift under a fixed overlay during
    /// a pan. Returns 1 when the cell centre is well outside the strip
    /// rect, 0 when it's fully inside, and a linear ramp across a
    /// `band`-pt buffer along each edge.
    ///
    /// The grid uses this so `panOffset != 0` doesn't reorder apps —
    /// the lattice filter freezes at pan = 0, the cluster pans
    /// rigidly, and any cell that ends up under the TabBar fades out
    /// instead of being shoved aside.
    public static func stripFadeOpacity(
        cellCenter: CGPoint,
        strip: CGRect?,
        band: CGFloat
    ) -> Double {
        guard let strip = strip, band > 0 else { return 1 }
        if strip.contains(cellCenter) { return 0 }
        let outer = strip.insetBy(dx: -band, dy: -band)
        if !outer.contains(cellCenter) { return 1 }
        let dx = max(strip.minX - cellCenter.x, cellCenter.x - strip.maxX, 0)
        let dy = max(strip.minY - cellCenter.y, cellCenter.y - strip.maxY, 0)
        let dist = max(dx, dy)
        return Double(min(1, dist / band))
    }


    /// any whose projected absolute centre lands inside `keepOut`. The
    /// effect is that the cluster grows a hex-shaped void around a fixed
    /// overlay (ProfileTabBar in grid mode) — surrounding cells fill in
    /// from the next-outer ring, so the whole constellation bends around
    /// the keep-out instead of being shoved aside after the fact.
    ///
    /// `originForCount` returns the (x, y) origin offset that maps a
    /// flat-grid cell at (row, col) to absolute view coords for a given
    /// candidate count. Letting the caller supply this avoids circular
    /// recomputation of bounds → origin → filter; in practice the
    /// renderer feeds in the unfiltered cluster's origin (a stable,
    /// good-enough estimate) and then re-centres after picking.
    /// Adaptive variant of `filteredSpiralLayout` that **preserves
    /// natural spiral positions** for apps whose natural slot doesn't
    /// fall in `keepOut`, and *only* relocates the few apps whose
    /// natural is blocked. Each blocked app is sent to the nearest
    /// unused, non-blocked candidate in the wider spiral pool.
    ///
    /// In contrast, `filteredSpiralLayout` does a single sequential
    /// pass — when one position is blocked, *every* later app shifts
    /// forward in spiral order. That cascade is fine when the keep-out
    /// is static, but during a pan it makes 60+ icons jump rings on
    /// every frame. The adaptive variant trades that for a stable
    /// "hole rolls along with the TabBar; far-away apps don't move"
    /// behaviour: only the apps right at the keep-out boundary swap
    /// between natural and outer-ring positions, animation hides the
    /// teleport.
    public static func adaptiveSpiralLayout(
        count: Int,
        spacing: CGFloat,
        verticalStretch: CGFloat,
        keepOut: CGRect?,
        candidateBuffer: Int = 64,
        originX: CGFloat,
        originY: CGFloat
    ) -> [(row: Int, col: Int)] {
        guard count > 0 else { return [] }
        guard let keepOut = keepOut, keepOut.width > 0, keepOut.height > 0 else {
            return spiralLayout(count: count)
        }
        let candidates = spiralLayout(count: count + max(candidateBuffer, 0))
        let absolute: ((row: Int, col: Int)) -> CGPoint = { rc in
            let p = center(
                row: rc.row,
                col: rc.col,
                spacing: spacing,
                verticalStretch: verticalStretch
            )
            return CGPoint(x: p.x + originX, y: p.y + originY)
        }
        struct HexCoord: Hashable { let row: Int; let col: Int }
        let key: ((row: Int, col: Int)) -> HexCoord = {
            HexCoord(row: $0.row, col: $0.col)
        }

        var picked: [(row: Int, col: Int)?] = Array(repeating: nil, count: count)
        var used = Set<HexCoord>()

        // Pass 1: assign each app to its natural spiral slot if that
        // slot isn't inside the keep-out.
        for K in 0..<count {
            let cand = candidates[K]
            if !keepOut.contains(absolute(cand)) {
                picked[K] = cand
                used.insert(key(cand))
            }
        }

        // Pass 2: for the remaining (blocked) apps, find the nearest
        // candidate that's both outside keep-out and not yet claimed.
        // Iterate in spiral order so the assignment is deterministic
        // across pan ticks — the same blocked-app set yields the same
        // outer slots, so an app that stays blocked across consecutive
        // frames doesn't bounce between outer positions.
        for K in 0..<count where picked[K] == nil {
            let naturalAbs = absolute(candidates[K])
            var best: (cand: (row: Int, col: Int), distSq: CGFloat)?
            for cand in candidates {
                if used.contains(key(cand)) { continue }
                let pt = absolute(cand)
                if keepOut.contains(pt) { continue }
                let dx = pt.x - naturalAbs.x
                let dy = pt.y - naturalAbs.y
                let distSq = dx * dx + dy * dy
                if best == nil || distSq < best!.distSq {
                    best = (cand, distSq)
                }
            }
            if let best {
                picked[K] = best.cand
                used.insert(key(best.cand))
            } else {
                // Pathological — the candidate pool ran out. Fall back
                // to the natural slot so the app at least renders.
                picked[K] = candidates[K]
            }
        }

        return picked.enumerated().map { idx, rc in rc ?? candidates[idx] }
    }

    public static func filteredSpiralLayout(
        count: Int,
        spacing: CGFloat,
        verticalStretch: CGFloat,
        keepOut: CGRect?,
        candidateBuffer: Int = 64,
        originX: CGFloat,
        originY: CGFloat
    ) -> [(row: Int, col: Int)] {
        guard count > 0 else { return [] }
        guard let keepOut = keepOut, keepOut.width > 0, keepOut.height > 0 else {
            return spiralLayout(count: count)
        }
        let candidates = spiralLayout(count: count + max(candidateBuffer, 0))
        var picked: [(row: Int, col: Int)] = []
        picked.reserveCapacity(count)
        for rc in candidates {
            let flat = center(
                row: rc.row,
                col: rc.col,
                spacing: spacing,
                verticalStretch: verticalStretch
            )
            let absolute = CGPoint(x: flat.x + originX, y: flat.y + originY)
            if keepOut.contains(absolute) { continue }
            picked.append(rc)
            if picked.count == count { break }
        }
        // Fall back to the unfiltered prefix if the buffer wasn't deep
        // enough — pathological case (massive keep-out swallowing the
        // candidate pool) where keeping any layout beats showing none.
        if picked.count < count {
            return spiralLayout(count: count)
        }
        return picked
    }


    /// (row, col) for each index, with row 0 at the top, columns left
    /// to right. The grid grows downward as items are added; rows are
    /// the smallest integer ≥ √count so the layout reads as a square
    /// before the user scales / pans.
    ///
    /// Index 0 lands at (0, 0) so the caller can centre the grid by
    /// translating to the average of the row/col centres.
    public static func indexLayout(count: Int, columns: Int) -> [(row: Int, col: Int)] {
        guard count > 0, columns > 0 else { return [] }
        return (0..<count).map { i in
            (row: i / columns, col: i % columns)
        }
    }
}
