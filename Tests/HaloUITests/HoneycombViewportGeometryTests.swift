import XCTest
import HaloCore
@testable import HaloUI

final class HoneycombViewportGeometryTests: XCTestCase {
    private let size = CGSize(width: 1440, height: 900)
    private let center = CGPoint(x: 720, y: 450)

    private func project(_ offset: CGPoint, pan: CGSize = .zero,
                         zoom: CGFloat = 1) -> HoneycombViewportGeometry.Projection {
        HoneycombViewportGeometry.project(
            offset: offset, viewCenter: center, focus: center, pan: pan,
            zoom: zoom, radius: 360, minimumScale: 0.48, maximumScale: 1.31)
    }

    func testStableLayoutReservesStripAndKeepsEveryApp() {
        let strip = CGRect(x: 625, y: 235, width: 190, height: 40)
        let layout = HoneycombViewportGeometry.layout(
            count: 224, spacing: 100, iconSize: 76, viewSize: size, exclusion: strip)
        XCTAssertEqual(layout.offsets.count, 224)
        let unique = Set(layout.offsets.map { "\($0.x),\($0.y)" })
        XCTAssertEqual(unique.count, 224)
        for offset in layout.offsets {
            XCTAssertFalse(strip.insetBy(dx: -76 * 0.52, dy: -76 * 0.52)
                .contains(CGPoint(x: center.x + offset.x, y: center.y + offset.y)))
        }
    }

    func testPanAcrossStripCannotTeleportOrExchangeSlots() {
        let layout = HoneycombViewportGeometry.layout(
            count: 180, spacing: 100, iconSize: 76, viewSize: size,
            exclusion: CGRect(x: 620, y: 250, width: 200, height: 40))
        for step in -120...120 {
            for offset in layout.offsets {
                let before = project(offset, pan: CGSize(width: step, height: 0)).center
                let after = project(offset, pan: CGSize(width: step + 1, height: 0)).center
                XCTAssertLessThanOrEqual(hypot(after.x - before.x, after.y - before.y), 1.001)
            }
        }
    }

    /// After the viewport settles the hole is re-reserved under the strip's
    /// current screen position, so the vacated area refills.
    func testSettledExclusionFollowsPanAndZoom() {
        let strip = CGRect(x: 625, y: 235, width: 190, height: 40)
        let pan = CGSize(width: 260, height: -140)
        let zoom: CGFloat = 1.4
        let canonical = HoneycombViewportGeometry.layoutExclusion(
            strip, viewSize: size, pan: pan, zoom: zoom)!
        XCTAssertEqual(HoneycombViewportGeometry.layoutExclusion(
            strip, viewSize: size, pan: .zero, zoom: 1), strip)
        let layout = HoneycombViewportGeometry.layout(
            count: 224, spacing: 100, iconSize: 76, viewSize: size, exclusion: canonical)
        XCTAssertEqual(layout.offsets.count, 224)
        let screenKeepOut = strip.insetBy(dx: -76 * 0.52 * zoom, dy: -76 * 0.52 * zoom)
        for offset in layout.offsets {
            let flat = CGPoint(x: center.x + offset.x * zoom + pan.width,
                               y: center.y + offset.y * zoom + pan.height)
            XCTAssertFalse(screenKeepOut.insetBy(dx: 0.01, dy: 0.01).contains(flat))
        }
        // The original canonical hole is no longer reserved.
        let stale = HoneycombViewportGeometry.layout(
            count: 224, spacing: 100, iconSize: 76, viewSize: size, exclusion: strip)
        XCTAssertNotEqual(stale.offsets, layout.offsets)
    }

    func testLensHasContinuousSlopeAtCenterAndRim() {
        let epsilon: CGFloat = 0.01
        let middle = project(.zero).scale
        XCTAssertEqual(middle, 1.31, accuracy: 0.00001)
        XCTAssertLessThan(abs(project(CGPoint(x: epsilon, y: 0)).scale - middle) / epsilon, 0.00001)
        let rim = project(CGPoint(x: 360, y: 0)).scale
        XCTAssertEqual(rim, 0.48, accuracy: 0.00001)
        XCTAssertLessThan(abs(project(CGPoint(x: 360 - epsilon, y: 0)).scale - rim) / epsilon, 0.00001)
        XCTAssertEqual(project(CGPoint(x: 600, y: 0)).scale, rim, accuracy: 0.00001)
    }

    func testPinchUsesSameProjectionBeforeAndAfterRelease() {
        let offset = CGPoint(x: 300, y: -160)
        let baseline: CGFloat = 0.8
        let magnification: CGFloat = 1.7
        let live = project(offset, zoom: baseline * magnification)
        let released = project(offset, zoom: 1.36)
        XCTAssertEqual(live.center.x, released.center.x, accuracy: 0.00001)
        XCTAssertEqual(live.center.y, released.center.y, accuracy: 0.00001)
        XCTAssertEqual(live.scale, released.scale, accuracy: 0.00001)
    }

    func testHitFrameUsesProjectedCenterAndActualScaledIcon() {
        let projection = project(CGPoint(x: 200, y: -100), zoom: 1.6)
        let frame = projection.iconFrame(size: 76 * 1.6)
        XCTAssertEqual(frame.midX, projection.center.x, accuracy: 0.00001)
        XCTAssertEqual(frame.midY, projection.center.y, accuracy: 0.00001)
        XCTAssertEqual(frame.width, 76 * 1.6 * projection.scale, accuracy: 0.00001)
        XCTAssertEqual(frame.width, frame.height)
    }

    func testProjectionRemainsFiniteForEmptyViewportAndZeroRadius() {
        let projection = HoneycombViewportGeometry.project(
            offset: .zero, viewCenter: .zero, focus: .zero, pan: .zero,
            zoom: 1, radius: 0, minimumScale: 0.48, maximumScale: 1.31)
        XCTAssertEqual(projection.center, .zero)
        XCTAssertTrue(projection.scale.isFinite)
        let layout = HoneycombViewportGeometry.layout(
            count: 0, spacing: 100, iconSize: 76, viewSize: .zero, exclusion: nil)
        XCTAssertTrue(layout.offsets.isEmpty)
    }

    func testCoastStopsAtBoundsAndIsIndependentOfFrameRate() {
        let coast = HoneycombViewportGeometry.Coast(
            origin: CGSize(width: 95, height: 0), predictedTravel: CGSize(width: 200, height: -100))
        let limits = CGSize(width: 100, height: 200)
        XCTAssertEqual(coast.value(at: 0, limits: limits).width, 95)
        XCTAssertEqual(coast.value(at: 1, limits: limits).width, 100)
        XCTAssertGreaterThan(coast.value(at: 1, limits: limits).height, -100)
        let sixtyFPS = coast.value(at: Double(30) / 60, limits: limits)
        let oneTwentyFPS = coast.value(at: Double(60) / 120, limits: limits)
        XCTAssertEqual(sixtyFPS, oneTwentyFPS)
        XCTAssertTrue(coast.isFinished(at: 2, limits: limits))
    }

    func testCoastCapsFastFlingWithoutChangingDirection() {
        let coast = HoneycombViewportGeometry.Coast(
            origin: .zero, predictedTravel: CGSize(width: 3000, height: 4000))
        XCTAssertEqual(hypot(coast.travel.width, coast.travel.height), 260, accuracy: 0.00001)
        XCTAssertEqual(coast.travel.width / coast.travel.height, 0.75, accuracy: 0.00001)
    }

    func testZoomRetargetPreservesPresentationValueAndVelocity() {
        let old = HoneycombViewportGeometry.ZoomSpring(origin: 1, target: 1.8, velocity: 0)
        let inFlight = old.sample(at: 0.045)
        let reversed = HoneycombViewportGeometry.ZoomSpring(
            origin: inFlight.value, target: 0.8, velocity: inFlight.velocity)
        XCTAssertEqual(reversed.sample(at: 0).value, inFlight.value, accuracy: 0.00001)
        XCTAssertEqual(reversed.sample(at: 0).velocity, inFlight.velocity, accuracy: 0.00001)
        XCTAssertTrue(reversed.isFinished(at: 2))
        XCTAssertEqual(reversed.sample(at: 2).value, 0.8, accuracy: 0.00001)
    }

    /// Compare the former moving keep-out hot path with a cached layout,
    /// using the same 224-app / 240-frame workload. Timings are diagnostic,
    /// not pass/fail assertions; run with HALO_PERF_LOG=1 for the local log.
    func testProjectionWorkloadBaseline() {
        let count = 224
        let strip = CGRect(x: 620, y: 250, width: 200, height: 40)
        let cached = HoneycombViewportGeometry.layout(
            count: count, spacing: 100, iconSize: 76, viewSize: size, exclusion: strip)
        let baselineSum: CGFloat = PerfSignpost.measure("watchBaseline240Frames") {
            var checksum: CGFloat = 0
            for frame in 0..<240 {
                let pan = CGFloat(frame) * 0.8
                let slots = HoneycombGeometry.adaptiveSpiralLayout(
                    count: count, spacing: 100, verticalStretch: 1.18,
                    keepOut: strip.insetBy(dx: -76 * 0.42, dy: -76 * 0.42),
                    originX: center.x + pan, originY: center.y)
                for slot in slots {
                    let offset = HoneycombGeometry.center(row: slot.row, col: slot.col,
                                                         spacing: 100, verticalStretch: 1.18)
                    checksum += project(offset, pan: CGSize(width: pan, height: 0)).center.x
                }
            }
            return checksum
        }
        let cachedSum: CGFloat = PerfSignpost.measure("watchCached240Frames") {
            var checksum: CGFloat = 0
            for frame in 0..<240 {
                for offset in cached.offsets {
                    checksum += project(offset, pan: CGSize(width: CGFloat(frame) * 0.8, height: 0)).center.x
                }
            }
            return checksum
        }
        XCTAssertTrue(baselineSum.isFinite && cachedSum.isFinite)
    }
}
