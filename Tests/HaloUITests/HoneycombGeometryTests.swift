import XCTest
@testable import HaloUI

/// Pure-math unit tests for the honeycomb grid helpers.
/// No SwiftUI / AppKit; all assertions are on `CGPoint` / `CGSize` /
/// `CGFloat` values that fall out of `HoneycombGeometry` directly.
final class HoneycombGeometryTests: XCTestCase {

    // MARK: - center

    func testEvenRowsAlignToOrigin() {
        // Even rows sit on the lattice's x-grid (no shift). Two cells
        // on the same even row are exactly `spacing` apart in x.
        let a = HoneycombGeometry.center(row: 0, col: 0, spacing: 100)
        let b = HoneycombGeometry.center(row: 0, col: 1, spacing: 100)
        XCTAssertEqual(a.x, 0,   accuracy: 0.001)
        XCTAssertEqual(b.x, 100, accuracy: 0.001)
        XCTAssertEqual(a.y, b.y, accuracy: 0.001)
    }

    func testOddRowsShiftRightByHalfSpacing() {
        // Odd rows offset by `spacing / 2` so adjacent rows interlock.
        let even = HoneycombGeometry.center(row: 0, col: 0, spacing: 100)
        let odd  = HoneycombGeometry.center(row: 1, col: 0, spacing: 100)
        XCTAssertEqual(odd.x - even.x, 50, accuracy: 0.001)
    }

    func testVerticalPitchIsSineSixty() {
        // Vertical pitch = spacing * sin(60°) ≈ spacing * 0.8660254.
        let r0 = HoneycombGeometry.center(row: 0, col: 0, spacing: 100)
        let r1 = HoneycombGeometry.center(row: 1, col: 0, spacing: 100)
        XCTAssertEqual(r1.y - r0.y, 86.60254, accuracy: 0.001)
    }

    // MARK: - fisheyeScale

    func testFisheyeAtCenterIsOne() {
        let s = HoneycombGeometry.fisheyeScale(distance: 0, maxRadius: 200)
        XCTAssertEqual(s, 1.0, accuracy: 0.0001)
    }

    func testFisheyeAtRimIsMinScale() {
        let s = HoneycombGeometry.fisheyeScale(
            distance: 200,
            maxRadius: 200,
            minScale: 0.4
        )
        XCTAssertEqual(s, 0.4, accuracy: 0.0001)
    }

    func testFisheyeBeyondRimClampsAtMin() {
        let s = HoneycombGeometry.fisheyeScale(
            distance: 500,
            maxRadius: 200,
            minScale: 0.4
        )
        XCTAssertEqual(s, 0.4, accuracy: 0.0001)
    }

    func testFisheyeMonotonicallyDecreases() {
        // Scale should fall as distance grows, regardless of curve.
        let near   = HoneycombGeometry.fisheyeScale(distance:  50, maxRadius: 200)
        let middle = HoneycombGeometry.fisheyeScale(distance: 100, maxRadius: 200)
        let far    = HoneycombGeometry.fisheyeScale(distance: 150, maxRadius: 200)
        XCTAssertGreaterThan(near, middle)
        XCTAssertGreaterThan(middle, far)
    }

    func testFisheyeZeroRadiusReturnsIdentity() {
        // Defensive: a zero or negative radius shouldn't crash; the
        // scale should fall back to identity.
        let s = HoneycombGeometry.fisheyeScale(distance: 100, maxRadius: 0)
        XCTAssertEqual(s, 1.0, accuracy: 0.0001)
    }

    // MARK: - fisheyeOffset

    func testFisheyeOffsetAtCenterIsZero() {
        let off = HoneycombGeometry.fisheyeOffset(
            position: CGPoint(x: 100, y: 100),
            viewCenter: CGPoint(x: 100, y: 100),
            maxRadius: 200
        )
        XCTAssertEqual(off.width,  0, accuracy: 0.0001)
        XCTAssertEqual(off.height, 0, accuracy: 0.0001)
    }

    func testFisheyeOffsetPullsTowardCenter() {
        // A point directly to the right of the centre should be pulled
        // back toward the centre (negative x offset).
        let off = HoneycombGeometry.fisheyeOffset(
            position: CGPoint(x: 200, y: 100),
            viewCenter: CGPoint(x: 100, y: 100),
            maxRadius: 100
        )
        XCTAssertLessThan(off.width, 0)
        XCTAssertEqual(off.height, 0, accuracy: 0.0001)
    }

    func testFisheyeOffsetGrowsWithDistance() {
        let near = HoneycombGeometry.fisheyeOffset(
            position: CGPoint(x: 130, y: 100),
            viewCenter: CGPoint(x: 100, y: 100),
            maxRadius: 100
        )
        let far = HoneycombGeometry.fisheyeOffset(
            position: CGPoint(x: 180, y: 100),
            viewCenter: CGPoint(x: 100, y: 100),
            maxRadius: 100
        )
        XCTAssertLessThan(far.width, near.width)  // both negative; far is more negative
    }


    // MARK: - searchAttractedPosition

    func testSearchAttractionKeepsZeroStrengthAtFlatPosition() {
        let flat = CGPoint(x: 300, y: 200)
        let out = HoneycombGeometry.searchAttractedPosition(
            flatPosition: flat,
            viewCenter: CGPoint(x: 100, y: 100),
            index: 0,
            strength: 0
        )
        XCTAssertEqual(out.x, flat.x, accuracy: 0.001)
        XCTAssertEqual(out.y, flat.y, accuracy: 0.001)
    }

    func testSearchAttractionPullsTowardCenterConstellation() {
        let flat = CGPoint(x: 300, y: 100)
        let out = HoneycombGeometry.searchAttractedPosition(
            flatPosition: flat,
            viewCenter: CGPoint(x: 100, y: 100),
            index: 0,
            strength: 0.5
        )
        XCTAssertLessThan(out.x, flat.x)
        XCTAssertEqual(out.y, flat.y, accuracy: 0.001)
    }

    func testSearchAttractionClampsStrength() {
        let flat = CGPoint(x: 300, y: 100)
        let center = CGPoint(x: 100, y: 100)
        let strong = HoneycombGeometry.searchAttractedPosition(
            flatPosition: flat,
            viewCenter: center,
            index: 0,
            strength: 2
        )
        // Index 0 target is 42pt to the right of centre. Strength > 1
        // should clamp exactly to that target, not overshoot past it.
        XCTAssertEqual(strong.x, 142, accuracy: 0.001)
        XCTAssertEqual(strong.y, 100, accuracy: 0.001)
    }



    // MARK: - interaction fields

    func testCommitCollapseOffsetPullsTowardAnchor() {
        let off = HoneycombGeometry.commitCollapseOffset(
            position: CGPoint(x: 0, y: 0),
            anchor: CGPoint(x: 100, y: 0),
            maxDistance: 200,
            strength: 0.2
        )
        XCTAssertGreaterThan(off.width, 0)
        XCTAssertEqual(off.height, 0, accuracy: 0.001)
        XCTAssertLessThanOrEqual(off.width, 28)
    }

    func testHoverRepelOffsetPushesAwayWithinRadius() {
        let off = HoneycombGeometry.hoverRepelOffset(
            position: CGPoint(x: 50, y: 0),
            hoverCenter: CGPoint(x: 0, y: 0),
            radius: 100,
            strength: 8
        )
        XCTAssertGreaterThan(off.width, 0)
        XCTAssertEqual(off.height, 0, accuracy: 0.001)
    }

    func testHoverRepelOffsetIgnoresOutsideRadius() {
        let off = HoneycombGeometry.hoverRepelOffset(
            position: CGPoint(x: 150, y: 0),
            hoverCenter: CGPoint(x: 0, y: 0),
            radius: 100,
            strength: 8
        )
        XCTAssertEqual(off.width, 0, accuracy: 0.001)
        XCTAssertEqual(off.height, 0, accuracy: 0.001)
    }

    // MARK: - displacedPosition

    func testDisplacedPositionLeavesOutsidePointAlone() {
        let point = CGPoint(x: 10, y: 10)
        let rect = CGRect(x: 40, y: 40, width: 80, height: 30)
        let out = HoneycombGeometry.displacedPosition(point, outOf: rect)
        XCTAssertEqual(out.x, point.x, accuracy: 0.001)
        XCTAssertEqual(out.y, point.y, accuracy: 0.001)
    }

    func testDisplacedPositionPushesInsidePointAwayFromCenter() {
        let rect = CGRect(x: 40, y: 40, width: 80, height: 30)
        let point = CGPoint(x: 80, y: 44)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let out = HoneycombGeometry.displacedPosition(
            point,
            outOf: rect,
            padding: 8
        )
        let before = hypot(point.x - center.x, point.y - center.y)
        let after = hypot(out.x - center.x, out.y - center.y)
        XCTAssertGreaterThan(after, before)
        XCTAssertLessThan(hypot(out.x - point.x, out.y - point.y), 36)
    }

    func testDisplacedPositionSoftlyMovesNearbyPointLessThanInsidePoint() {
        let rect = CGRect(x: 40, y: 40, width: 80, height: 30)
        let inside = CGPoint(x: 80, y: 44)
        let nearby = CGPoint(x: 80, y: 82)
        let pushedInside = HoneycombGeometry.displacedPosition(inside, outOf: rect, padding: 12)
        let pushedNearby = HoneycombGeometry.displacedPosition(nearby, outOf: rect, padding: 12)
        let insideMove = hypot(pushedInside.x - inside.x, pushedInside.y - inside.y)
        let nearbyMove = hypot(pushedNearby.x - nearby.x, pushedNearby.y - nearby.y)
        XCTAssertGreaterThan(insideMove, nearbyMove)
        XCTAssertGreaterThan(nearbyMove, 0)
    }

    func testResolvedCenterMovesFootprintOutsideExclusion() {
        let exclusion = CGRect(x: 100, y: 100, width: 120, height: 44)
        let footprint = CGSize(width: 88, height: 96)
        let center = CGPoint(x: 160, y: 122)
        let resolved = HoneycombGeometry.resolvedCenter(
            center,
            avoiding: exclusion,
            footprint: footprint,
            margin: 8
        )
        let visible = CGRect(
            x: resolved.x - footprint.width / 2,
            y: resolved.y - footprint.height / 2,
            width: footprint.width,
            height: footprint.height
        )
        XCTAssertFalse(visible.intersects(exclusion.insetBy(dx: -8, dy: -8)))
    }

    func testResolvedCenterLeavesSafePointAlone() {
        let exclusion = CGRect(x: 100, y: 100, width: 120, height: 44)
        let center = CGPoint(x: 40, y: 40)
        let resolved = HoneycombGeometry.resolvedCenter(
            center,
            avoiding: exclusion,
            footprint: CGSize(width: 70, height: 80),
            margin: 8
        )
        XCTAssertEqual(resolved.x, center.x, accuracy: 0.001)
        XCTAssertEqual(resolved.y, center.y, accuracy: 0.001)
    }

    func testResolvedProjectedCenterSurvivesSecondProjectionNearProfileStrip() {
        let strip = CGRect(x: 972, y: 532, width: 304, height: 78)
        let focus = CGPoint(x: 960, y: 526)
        let radius: CGFloat = 520
        let footprint = CGSize(width: 132, height: 108)
        let candidates = [
            CGPoint(x: 1008, y: 642),
            CGPoint(x: 1084, y: 664),
            CGPoint(x: 1188, y: 652),
            CGPoint(x: 1282, y: 610),
            CGPoint(x: 1118, y: 492),
        ]

        for base in candidates {
            let resolved = HoneycombGeometry.resolvedProjectedCenter(
                base,
                projectedCenter: { point in
                    let offset = HoneycombGeometry.fisheyeOffset(
                        position: point,
                        viewCenter: focus,
                        maxRadius: radius,
                        strength: 0.12
                    )
                    return CGPoint(x: point.x + offset.width, y: point.y + offset.height)
                },
                footprint: { _ in footprint },
                avoiding: strip,
                margin: 10
            )
            let offset = HoneycombGeometry.fisheyeOffset(
                position: resolved,
                viewCenter: focus,
                maxRadius: radius,
                strength: 0.12
            )
            let rendered = CGPoint(x: resolved.x + offset.width, y: resolved.y + offset.height)
            let visible = CGRect(
                x: rendered.x - footprint.width / 2,
                y: rendered.y - footprint.height / 2,
                width: footprint.width,
                height: footprint.height
            )
            XCTAssertFalse(
                visible.intersects(strip.insetBy(dx: -10, dy: -10)),
                "base \(base) resolved to \(resolved), rendered \(rendered), visible \(visible)"
            )
        }
    }


    // MARK: - spiralLayout

    func testSpiralLayoutStartsAtCenter() {
        let layout = HoneycombGeometry.spiralLayout(count: 1)
        XCTAssertEqual(layout.count, 1)
        XCTAssertEqual(layout[0].row, 0)
        XCTAssertEqual(layout[0].col, 0)
    }

    func testSpiralLayoutFirstRingHasSixNeighbours() {
        let layout = HoneycombGeometry.spiralLayout(count: 7)
        XCTAssertEqual(layout.count, 7)
        let unique = Set(layout.map { "\($0.row),\($0.col)" })
        XCTAssertEqual(unique.count, 7)
        XCTAssertTrue(unique.contains("0,0"))
    }

    func testSpiralLayoutIsDistanceOrdered() {
        let layout = HoneycombGeometry.spiralLayout(count: 48)
        var previous: CGFloat = 0
        for rc in layout {
            let point = HoneycombGeometry.center(row: rc.row, col: rc.col, spacing: 1)
            let distance = hypot(point.x, point.y)
            XCTAssertGreaterThanOrEqual(distance + 0.0001, previous)
            previous = distance
        }
    }

    func testLayoutBoundsContainsSpiralCenters() {
        let layout = HoneycombGeometry.spiralLayout(count: 19)
        let bounds = HoneycombGeometry.layoutBounds(layout: layout, spacing: 80)
        for rc in layout {
            let point = HoneycombGeometry.center(row: rc.row, col: rc.col, spacing: 80)
            XCTAssertTrue(bounds.insetBy(dx: -0.001, dy: -0.001).contains(point))
        }
    }

    // MARK: - indexLayout

    func testIndexLayoutEmpty() {
        XCTAssertTrue(HoneycombGeometry.indexLayout(count: 0, columns: 4).isEmpty)
    }

    func testIndexLayoutFillsRowsLeftToRight() {
        let l = HoneycombGeometry.indexLayout(count: 7, columns: 3)
        XCTAssertEqual(l.count, 7)
        XCTAssertEqual(l[0].row, 0); XCTAssertEqual(l[0].col, 0)
        XCTAssertEqual(l[2].row, 0); XCTAssertEqual(l[2].col, 2)
        XCTAssertEqual(l[3].row, 1); XCTAssertEqual(l[3].col, 0)
        XCTAssertEqual(l[6].row, 2); XCTAssertEqual(l[6].col, 0)
    }

    // MARK: - adaptiveSpiralLayout keep-out invariant

    /// Critical invariant: no returned cell centre lands inside the keep-out
    /// rect regardless of its position, size, or app count.
    func testAdaptiveSpiralLayoutNoCellInsideKeepOut() {
        let spacing: CGFloat = 88
        let vStretch: CGFloat = 1.18
        let keepOut = CGRect(x: 600, y: 820, width: 240, height: 36)
        let originX: CGFloat = 720
        let originY: CGFloat = 450

        for count in [1, 7, 20, 50, 100, 200] {
            let layout = HoneycombGeometry.adaptiveSpiralLayout(
                count: count,
                spacing: spacing,
                verticalStretch: vStretch,
                keepOut: keepOut,
                originX: originX,
                originY: originY
            )
            XCTAssertEqual(layout.count, count, "count=\(count): wrong number of positions")
            for (i, rc) in layout.enumerated() {
                let flat = HoneycombGeometry.center(
                    row: rc.row, col: rc.col,
                    spacing: spacing, verticalStretch: vStretch
                )
                let abs = CGPoint(x: flat.x + originX, y: flat.y + originY)
                XCTAssertFalse(
                    keepOut.contains(abs),
                    "count=\(count) idx=\(i) at (\(abs.x),\(abs.y)) inside keepOut \(keepOut)"
                )
            }
        }
    }

    /// When keepOut is nil the function must return the plain spiralLayout.
    func testAdaptiveSpiralLayoutNilKeepOutMatchesSpiralLayout() {
        let count = 30
        let adaptive = HoneycombGeometry.adaptiveSpiralLayout(
            count: count,
            spacing: 88,
            verticalStretch: 1.18,
            keepOut: nil,
            originX: 0,
            originY: 0
        )
        let plain = HoneycombGeometry.spiralLayout(count: count)
        XCTAssertEqual(adaptive.map { "\($0.row),\($0.col)" },
                       plain.map   { "\($0.row),\($0.col)" })
    }

    /// Exhausted candidate buffer (keepOut swallows most of the pool)
    /// must still return `count` positions without crashing.
    func testAdaptiveSpiralLayoutExhaustedBufferDoesNotCrash() {
        // A keepOut so large it covers virtually the entire candidate pool.
        let keepOut = CGRect(x: -2000, y: -2000, width: 4000, height: 4000)
        let layout = HoneycombGeometry.adaptiveSpiralLayout(
            count: 10,
            spacing: 88,
            verticalStretch: 1.18,
            keepOut: keepOut,
            candidateBuffer: 0,
            originX: 0,
            originY: 0
        )
        XCTAssertEqual(layout.count, 10)
    }
}
