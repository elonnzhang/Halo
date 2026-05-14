import XCTest
import CoreGraphics
@testable import HaloUI

/// Coverage for the wider invisible "reach" hit-test radius. The cursor
/// counts as hovering a sector anywhere within `reachRadius` of the wheel
/// centre (typically several times the visible disc), but past that radius
/// the call returns nil so the user keeps a "drag the cursor away to
/// cancel" affordance.
final class RadialReachHitTestTests: XCTestCase {

    private let inner: CGFloat = 56     // deadzoneDiameter / 2
    private let wheel: CGFloat = 220    // haloDiameter / 2 — visible rim
    private let reach: CGFloat = 660    // reachDiameter / 2 = wheel * 3

    // A point well outside the visible wheel but inside the reach radius
    // should still resolve to the sector its angle points at.
    func test_pointOutsideWheelButInsideReach_hitsCorrectSector() {
        // 12 o'clock direction, distance 400 — past `wheel = 220` but well
        // within `reach = 660`. Slot 0 is at 12 o'clock for an 8-slot wheel.
        let idx = RadialGeometry.sectorIndex(
            for: CGPoint(x: 0, y: 400),
            sectorCount: 8,
            innerRadius: inner,
            outerRadius: reach
        )
        XCTAssertEqual(idx, 0)
    }

    // 6 o'clock at the same far distance: slot 4 (opposite of slot 0).
    func test_pointOutsideWheelOpposite_hitsOppositeSector() {
        let idx = RadialGeometry.sectorIndex(
            for: CGPoint(x: 0, y: -400),
            sectorCount: 8,
            innerRadius: inner,
            outerRadius: reach
        )
        XCTAssertEqual(idx, 4)
    }

    // Past the reach radius: the cursor is "off the wheel" and no slot is
    // selected. This is the user's escape hatch — drag past the reach
    // boundary, release the trigger, no app launches.
    func test_pointBeyondReach_returnsNil() {
        let idx = RadialGeometry.sectorIndex(
            for: CGPoint(x: 0, y: reach + 50),
            sectorCount: 8,
            innerRadius: inner,
            outerRadius: reach
        )
        XCTAssertNil(idx)
    }

    // Centre deadzone is unchanged by the reach extension: pointing at the
    // hub still returns nil.
    func test_pointInsideDeadzone_returnsNil() {
        let idx = RadialGeometry.sectorIndex(
            for: CGPoint(x: 10, y: 10),
            sectorCount: 8,
            innerRadius: inner,
            outerRadius: reach
        )
        XCTAssertNil(idx)
    }

    // Sweep four cardinal directions at far distance and confirm each
    // resolves to its expected sector (slot 0 / 2 / 4 / 6 on a wheel of 8).
    func test_cardinalSweep_atReachEdge_hitsExpectedSectors() {
        let r: CGFloat = 600  // inside reach 660
        XCTAssertEqual(
            RadialGeometry.sectorIndex(
                for: CGPoint(x: 0, y: r),
                sectorCount: 8, innerRadius: inner, outerRadius: reach),
            0, "12 o'clock → slot 0"
        )
        XCTAssertEqual(
            RadialGeometry.sectorIndex(
                for: CGPoint(x: r, y: 0),
                sectorCount: 8, innerRadius: inner, outerRadius: reach),
            2, "3 o'clock → slot 2"
        )
        XCTAssertEqual(
            RadialGeometry.sectorIndex(
                for: CGPoint(x: 0, y: -r),
                sectorCount: 8, innerRadius: inner, outerRadius: reach),
            4, "6 o'clock → slot 4"
        )
        XCTAssertEqual(
            RadialGeometry.sectorIndex(
                for: CGPoint(x: -r, y: 0),
                sectorCount: 8, innerRadius: inner, outerRadius: reach),
            6, "9 o'clock → slot 6"
        )
    }

    // The boundary case: a point exactly on the reach circle counts as
    // inside (the comparison is `<= outerRadius`).
    func test_pointExactlyAtReachBoundary_hitsSector() {
        let idx = RadialGeometry.sectorIndex(
            for: CGPoint(x: 0, y: reach),
            sectorCount: 8,
            innerRadius: inner,
            outerRadius: reach
        )
        XCTAssertEqual(idx, 0)
    }
}
