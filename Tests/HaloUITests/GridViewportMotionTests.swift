import XCTest
@testable import HaloUI

@MainActor
final class GridViewportMotionTests: XCTestCase {
    func testReducedMotionDoesNotStartCoastOrZoomSpring() {
        let state = GridState()
        state.viewportPanLimits = CGSize(width: 1000, height: 1000)
        let motion = GridViewportMotion(state: state)
        motion.coast(by: CGSize(width: 100, height: 0), reduceMotion: true)
        XCTAssertFalse(state.isViewportMoving)
        XCTAssertEqual(state.panOffset, .zero)
        motion.zoom(by: 0.4, reduceMotion: true)
        XCTAssertEqual(state.zoomLevel, 1.4, accuracy: 0.00001)
        XCTAssertFalse(state.isViewportMoving)
    }

    func testNewGestureCancelsInertiaAtItsVisiblePosition() {
        let state = GridState()
        state.viewportPanLimits = CGSize(width: 1000, height: 1000)
        let motion = GridViewportMotion(state: state)
        motion.coast(by: CGSize(width: 120, height: -40), reduceMotion: false)
        motion.advance(at: ProcessInfo.processInfo.systemUptime + 0.1)
        let visible = state.panOffset
        motion.beginGesture()
        XCTAssertEqual(state.panOffset, visible)
        motion.advance(at: ProcessInfo.processInfo.systemUptime + 1)
        XCTAssertEqual(state.panOffset, visible)
        motion.stop()
    }

    func testWheelNotchesAccumulateAndConvergeToClampedTarget() {
        let state = GridState()
        let motion = GridViewportMotion(state: state)
        motion.zoom(by: 0.1, reduceMotion: false)
        motion.zoom(by: 0.1, reduceMotion: false)
        motion.advance(at: ProcessInfo.processInfo.systemUptime + 2)
        XCTAssertEqual(state.zoomLevel, 1.2, accuracy: 0.00001)
        XCTAssertFalse(state.isViewportMoving)
        motion.zoom(by: 100, reduceMotion: false)
        motion.advance(at: ProcessInfo.processInfo.systemUptime + 2)
        XCTAssertEqual(state.zoomLevel, 2.5)
        motion.zoom(by: -100, reduceMotion: false)
        motion.advance(at: ProcessInfo.processInfo.systemUptime + 2)
        XCTAssertEqual(state.zoomLevel, 0.5)
    }

    func testNativeTrackpadPanCancelsSyntheticMotionAndUsesSharedBounds() {
        let state = GridState()
        state.viewportPanLimits = CGSize(width: 80, height: 60)
        state.coastViewport(by: CGSize(width: 200, height: 0), reduceMotion: false)
        state.panViewport(by: CGSize(width: -300, height: 150))
        XCTAssertEqual(state.panOffset, CGSize(width: -80, height: 60))
        XCTAssertFalse(state.isViewportMoving)
        XCTAssertTrue(state.pointerSelectionSuppressed)
    }

    func testResetCancelsPendingMotionAndClearsHitFrames() async {
        let state = GridState()
        state.viewportPanLimits = CGSize(width: 1000, height: 1000)
        state.cellFrames = ["test": CGRect(x: 0, y: 0, width: 80, height: 80)]
        state.coastViewport(by: CGSize(width: 180, height: 0), reduceMotion: false)
        state.resetViewport()
        await Task.yield()
        XCTAssertEqual(state.panOffset, .zero)
        XCTAssertEqual(state.zoomLevel, 1)
        XCTAssertFalse(state.isViewportMoving)
        XCTAssertTrue(state.cellFrames.isEmpty)
    }

    func testScrollAgainstPanBoundaryDoesNotSuppressHoverIndefinitely() {
        let state = GridState()
        state.viewportPanLimits = CGSize(width: 80, height: 60)
        state.panOffset = state.viewportPanLimits
        state.panViewport(by: CGSize(width: 100, height: 100))
        XCTAssertEqual(state.panOffset, state.viewportPanLimits)
        XCTAssertFalse(state.pointerSelectionSuppressed)
    }

    func testHoverUsesActualRimFootprintAndPausesDuringMotion() {
        let state = GridState()
        state.apps = [GridState.GridApp(bundleID: "rim", name: "Rim", url: URL(fileURLWithPath: "/Rim.app"))]
        state.cellFrames = ["rim": CGRect(x: 90, y: 90, width: 20, height: 20)]
        state.hoverSelect(at: CGPoint(x: 125, y: 100), iconSize: 76)
        XCTAssertNil(state.selectedBundleID)
        state.hoverSelect(at: CGPoint(x: 100, y: 100), iconSize: 76)
        XCTAssertEqual(state.selectedBundleID, "rim")
        state.isViewportMoving = true
        state.hoverSelect(at: CGPoint(x: 1000, y: 1000), iconSize: 76)
        XCTAssertEqual(state.selectedBundleID, "rim")
    }
}
