import XCTest
import CoreGraphics
@testable import HaloUI

/// Regression coverage for the panelScale hit-test bug.
///
/// History: `RadialView.sectorIndex(at:)` was called by DragGesture with
/// `value.location` in the **scaled** view's coord space (because
/// `.gesture` was attached after `.scaleEffect(panelScale)`), but its
/// math used the **unscaled** `totalDiameter` as its frame of reference.
/// Result: with `panelScale = 1.3`, a click on slot 0 (12 o'clock) was
/// hit-tested into slot 1 — visible as the "next slot lights up briefly"
/// flash, and silently commits the wrong app.
///
/// The fix introduces `RadialGeometry.sectorIndex(forGestureLocation:…)`
/// which divides the gesture location by `panelScale` before running
/// the unscaled geometry math. These tests pin the divide in place.
final class RadialGeometryHitTestTests: XCTestCase {

    private let totalDiameter: CGFloat = 580   // matches HaloUI.Geometry.totalDiameter @ default
    private let inner: CGFloat = 56            // deadzoneDiameter / 2
    private let outer: CGFloat = 220           // haloDiameter / 2

    // Click at 12 o'clock under panelScale = 1.0: should hit slot 0.
    func test_topCenterClick_atScaleOne_hitsSlotZero() {
        // Slot 0 icon center is at (centerX, centerY - iconRadius).
        // With default iconRadius ~ 134 and totalDiameter = 580,
        // icon-relative position in scaled view at scale=1 is (290, 156).
        let idx = RadialGeometry.sectorIndex(
            forGestureLocation: CGPoint(x: 290, y: 156),
            panelScale: 1.0,
            totalDiameter: totalDiameter,
            sectorCount: 8,
            innerRadius: inner,
            outerRadius: outer
        )
        XCTAssertEqual(idx, 0)
    }

    // Same click target at panelScale = 1.3: the visible icon has moved
    // out (now at ~(377, 203) in scaled view coords). Hit-test must
    // STILL return slot 0 — otherwise we have the original bug back.
    func test_topCenterClick_atScale1_3_stillHitsSlotZero() {
        let idx = RadialGeometry.sectorIndex(
            forGestureLocation: CGPoint(x: 290 * 1.3, y: 156 * 1.3),
            panelScale: 1.3,
            totalDiameter: totalDiameter,
            sectorCount: 8,
            innerRadius: inner,
            outerRadius: outer
        )
        XCTAssertEqual(idx, 0)
    }

    // Center of the scaled view (where the hub lives) returns nil.
    // Pre-fix this returned a sector for any panelScale > 1.0 because
    // the click position fell outside innerRadius in the unscaled math.
    func test_centerClick_atScale1_3_returnsNilForHub() {
        let centerScaled = totalDiameter * 1.3 / 2
        let idx = RadialGeometry.sectorIndex(
            forGestureLocation: CGPoint(x: centerScaled, y: centerScaled),
            panelScale: 1.3,
            totalDiameter: totalDiameter,
            sectorCount: 8,
            innerRadius: inner,
            outerRadius: outer
        )
        XCTAssertNil(idx)
    }

    // Slot 4 (6 o'clock) at scale = 1.5 — slot order verifies the
    // helper isn't mirroring or swapping axes.
    func test_bottomCenterClick_atScale1_5_hitsSlot4() {
        // Below the center: y = centerY + iconRadius ~ 290 + 134 = 424.
        let idx = RadialGeometry.sectorIndex(
            forGestureLocation: CGPoint(x: 290 * 1.5, y: 424 * 1.5),
            panelScale: 1.5,
            totalDiameter: totalDiameter,
            sectorCount: 8,
            innerRadius: inner,
            outerRadius: outer
        )
        XCTAssertEqual(idx, 4)
    }

    // panelScale = 0 (degenerate) clamps to the small positive epsilon
    // and doesn't divide by zero.
    func test_zeroPanelScale_doesNotCrash() {
        let idx = RadialGeometry.sectorIndex(
            forGestureLocation: CGPoint(x: 100, y: 100),
            panelScale: 0,
            totalDiameter: totalDiameter,
            sectorCount: 8,
            innerRadius: inner,
            outerRadius: outer
        )
        // Whatever the math computes, the call must return without
        // crashing. The exact result depends on the clamp epsilon —
        // we only care that nothing throws / traps.
        _ = idx
    }
}
