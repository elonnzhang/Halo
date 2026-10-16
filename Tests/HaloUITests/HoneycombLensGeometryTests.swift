import XCTest
@testable import HaloUI

@MainActor
final class HoneycombLensGeometryTests: XCTestCase {
    private let m = HoneycombLensGeometry.Metrics.scaled(1)
    private let view = CGSize(width: 1440, height: 900)

    func testMiddleItemIsLargeAndFacesViewer() {
        let p = HoneycombLensGeometry.place(cell: .zero, at: .zero, viewSize: view, metrics: m)
        XCTAssertEqual(p.center, CGPoint(x: 720, y: 450))
        XCTAssertEqual(p.size, m.large, accuracy: 0.0001)
        XCTAssertEqual(p.squash, 1, accuracy: 0.0001)
        XCTAssertEqual(p.opacity, 1, accuracy: 0.0001)
    }

    func testSizeAndSpacingShrinkMonotonicallyOutward() {
        var lastSize = CGFloat.infinity, lastGap = CGFloat.infinity, lastDrawn: CGFloat = 0
        for step in 1...12 {
            let d = CGFloat(step) * m.spacing
            let drawn = m.magnified(d)
            XCTAssertLessThan(m.size(d), lastSize)
            XCTAssertLessThan(drawn - lastDrawn, lastGap)
            XCTAssertGreaterThan(m.tilt(d), 0)
            lastGap = drawn - lastDrawn
            lastDrawn = drawn
            lastSize = m.size(d)
        }
        XCTAssertLessThan(m.tilt(10_000), HoneycombLensGeometry.maxTilt + 0.0001)
    }

    func testEdgeItemsShrinkToTinyAndFade() {
        // Far enough out that the magnified position lands outside the view.
        let p = HoneycombLensGeometry.place(cell: CGPoint(x: 4000, y: 0), at: .zero,
                                            viewSize: view, metrics: m)
        XCTAssertEqual(p.size, m.tiny, accuracy: 0.0001)
        XCTAssertEqual(p.opacity, 0, accuracy: 0.0001)
        XCTAssertNil(HoneycombLensGeometry.hit([(0, p)], at: p.center))
    }

    func testLensStretchFollowsScreenAspect() {
        XCTAssertEqual(HoneycombLensGeometry.stretch(for: view), CGSize(width: 1.6, height: 1))
        XCTAssertEqual(HoneycombLensGeometry.stretch(for: CGSize(width: 900, height: 1440)),
                       CGSize(width: 1, height: 1.6))
        XCTAssertEqual(HoneycombLensGeometry.stretch(for: CGSize(width: 5120, height: 1000)).width,
                       HoneycombLensGeometry.maxStretch)
        XCTAssertEqual(HoneycombLensGeometry.stretch(for: .zero), CGSize(width: 1, height: 1))
    }

    func testEllipticalLensKeepsCentreIsotropicAndFallsOffSlowerAlongLongAxis() {
        let e = HoneycombLensGeometry.Metrics.scaled(1, viewSize: view)
        let near = m.spacing * 0.01
        let h0 = HoneycombLensGeometry.place(cell: CGPoint(x: near, y: 0), at: .zero, viewSize: view, metrics: e)
        let v0 = HoneycombLensGeometry.place(cell: CGPoint(x: 0, y: near), at: .zero, viewSize: view, metrics: e)
        XCTAssertEqual(h0.center.x - 720, v0.center.y - 450, accuracy: 0.01)
        let far = m.spacing * 3
        let h = HoneycombLensGeometry.place(cell: CGPoint(x: far, y: 0), at: .zero, viewSize: view, metrics: e)
        let v = HoneycombLensGeometry.place(cell: CGPoint(x: 0, y: far), at: .zero, viewSize: view, metrics: e)
        XCTAssertGreaterThan(h.size, v.size)
        XCTAssertGreaterThan(h.squash, v.squash)
        XCTAssertGreaterThan(h.center.x - 720, v.center.y - 450)
    }

    func testCellsFillAnEllipseOfTheScreenProportions() {
        let stretch = HoneycombLensGeometry.stretch(for: view)
        let cells = HoneycombLensGeometry.cells(count: 224, spacing: 100, stretch: stretch)
        XCTAssertEqual(cells.count, 224)
        XCTAssertEqual(Set(cells.map { "\($0.x),\($0.y)" }).count, 224)
        XCTAssertEqual(cells[0], .zero)
        let b = HoneycombLensGeometry.bounds(of: cells)
        XCTAssertEqual(b.width / b.height, stretch.width, accuracy: 0.25)
        let round = HoneycombLensGeometry.bounds(of: HoneycombLensGeometry.cells(count: 224, spacing: 100))
        XCTAssertEqual(round.width / round.height, 1, accuracy: 0.2)
    }

    func testTiltDefaultsTo27AndFollowsSetting() {
        XCTAssertEqual(HoneycombLensGeometry.maxTilt, 27)
        XCTAssertEqual(m.tilt(100_000), 27, accuracy: 0.001)
        let flat = HoneycombLensGeometry.Metrics.scaled(1, maxTilt: 0)
        XCTAssertEqual(flat.tilt(m.spacing * 6), 0)
        let p = HoneycombLensGeometry.place(cell: CGPoint(x: m.spacing * 3, y: 0), at: .zero,
                                            viewSize: view, metrics: flat)
        XCTAssertEqual(p.squash, 1, accuracy: 0.0001)
    }

    func testManualEllipseRatioOverridesScreenAspect() {
        XCTAssertEqual(HoneycombLensGeometry.stretch(for: view, ratio: 1), CGSize(width: 1, height: 1))
        XCTAssertEqual(HoneycombLensGeometry.stretch(for: view, ratio: 2), CGSize(width: 2, height: 1))
        XCTAssertEqual(HoneycombLensGeometry.stretch(for: CGSize(width: 900, height: 1440), ratio: 1.3),
                       CGSize(width: 1, height: 1.3))
        XCTAssertEqual(HoneycombLensGeometry.stretch(for: view, ratio: 9).width,
                       HoneycombLensGeometry.maxStretch)
        let e = HoneycombLensGeometry.Metrics.scaled(1, viewSize: view, ratio: 1.2)
        XCTAssertEqual(e.stretch, CGSize(width: 1.2, height: 1))
    }

    func testRimOpacityMatchesAllAndScalesWithDepth() {
        let depth = HoneycombGeometry.rimDepthDefault
        XCTAssertEqual(HoneycombGeometry.rimOpacity(distance: 0, radius: 360, depth: depth), 1)
        XCTAssertEqual(HoneycombGeometry.rimOpacity(distance: 360, radius: 360, depth: depth), 0.64,
                       accuracy: 0.0001)
        XCTAssertEqual(HoneycombGeometry.rimOpacity(distance: 900, radius: 360, depth: depth), 0.64,
                       accuracy: 0.0001)
        XCTAssertEqual(HoneycombGeometry.rimOpacity(distance: 180, radius: 360, depth: depth),
                       1 - 0.36 * 0.25, accuracy: 0.0001)
        XCTAssertEqual(HoneycombGeometry.rimOpacity(distance: 360, radius: 360, depth: 0), 1)
        XCTAssertEqual(HoneycombGeometry.rimOpacity(distance: 360, radius: 0, depth: 0.5), 0.5,
                       accuracy: 0.0001)
    }

    // MARK: - Profile strip reservation

    private let strip = CGRect(x: 520, y: 600, width: 400, height: 44)

    func testLensCentreAvoidsStripOnlyWhenCovered() {
        XCTAssertEqual(HoneycombLensGeometry.lensCentre(viewSize: view, strip: nil, clearance: 70),
                       CGPoint(x: 720, y: 450))
        XCTAssertEqual(HoneycombLensGeometry.lensCentre(viewSize: view, strip: strip, clearance: 70),
                       CGPoint(x: 720, y: 450))
        let over = CGRect(x: 520, y: 430, width: 400, height: 44)
        XCTAssertEqual(HoneycombLensGeometry.lensCentre(viewSize: view, strip: over, clearance: 70).y,
                       over.minY - 70)
    }

    func testAssignmentMovesOnlyBlockedAppsAndClearsTheStrip() {
        let count = 120
        let slots = HoneycombLensGeometry.cells(count: count + HoneycombLensGeometry.spareCells,
                                                spacing: m.spacing)
        let centre = CGPoint(x: 720, y: 450)
        let blocked = HoneycombLensGeometry.blockedSlots(slots, at: .zero, viewSize: view,
                                                         centre: centre, metrics: m, strip: strip)
        XCTAssertFalse(blocked.isEmpty)
        let assignment = HoneycombLensGeometry.assign(count: count, slots: slots,
                                                      blocked: blocked, metrics: m)
        XCTAssertEqual(assignment.count, count)
        XCTAssertEqual(Set(assignment).count, count)
        for (app, slot) in assignment.enumerated() {
            XCTAssertFalse(blocked.contains(slot))
            if !blocked.contains(app) { XCTAssertEqual(slot, app) }
        }
    }

    func testNoStripKeepsNaturalOrder() {
        let slots = HoneycombLensGeometry.cells(count: 30, spacing: m.spacing)
        XCTAssertEqual(HoneycombLensGeometry.assign(count: 20, slots: slots, blocked: [], metrics: m),
                       Array(0..<20))
    }

    func testModelReflowsAtRestAndKeepsFocalAppCentred() {
        let state = GridState()
        let lens = state.lens
        let ids = (0..<120).map { "app.\($0)" }
        lens.sync(ids: ids, metrics: m)
        let natural = lens.cells
        let centre = CGPoint(x: 720, y: 450)
        lens.reserve(.init(viewSize: view, centre: centre, strip: strip))
        XCTAssertNotEqual(lens.cells, natural)
        XCTAssertEqual(lens.at, lens.cells[0])
        XCTAssertEqual(lens.centredID, "app.0")
        for cell in lens.cells {
            let p = HoneycombLensGeometry.place(cell: cell, at: lens.at, viewSize: view,
                                                metrics: m, centre: centre)
            XCTAssertFalse(strip.insetBy(dx: -p.size / 2, dy: -p.size / 2).contains(p.center))
        }
        // Clearing the strip restores the natural spiral.
        lens.reserve(.init(viewSize: view, centre: centre, strip: nil))
        XCTAssertEqual(lens.cells, natural)
    }

    func testHoverSelectsInPlaceAndFallsBackToCentredApp() {
        let state = GridState()
        state.apps = ["a", "b"].map {
            GridState.GridApp(bundleID: $0, name: $0, url: URL(fileURLWithPath: "/\($0).app"))
        }
        state.lens.sync(ids: ["a", "b"], metrics: m)
        let at = state.lens.at
        state.cellFrames = ["a": CGRect(x: 0, y: 0, width: 40, height: 40),
                            "b": CGRect(x: 100, y: 0, width: 40, height: 40)]
        state.hoverSelect(at: CGPoint(x: 120, y: 20), iconSize: 76)
        XCTAssertEqual(state.selectedBundleID, "b")
        XCTAssertEqual(state.lens.at, at, "hover must not pan the lens")
        state.hoverSelect(at: CGPoint(x: 600, y: 600), iconSize: 76)
        XCTAssertEqual(state.selectedBundleID, "a")
    }

    func testRubberBandSlowsTravelPastBounds() {
        let bounds = CGRect(x: -100, y: -100, width: 200, height: 200)
        let inside = HoneycombLensGeometry.pan(.zero, by: CGSize(width: 10, height: 0), within: bounds)
        XCTAssertEqual(inside.x, 10)
        let past = HoneycombLensGeometry.pan(CGPoint(x: 120, y: 0), by: CGSize(width: 10, height: 0),
                                             within: bounds)
        XCTAssertEqual(past.x, 120 + 10 * HoneycombLensGeometry.rubber, accuracy: 0.0001)
        let back = HoneycombLensGeometry.pan(CGPoint(x: 120, y: 0), by: CGSize(width: -10, height: 0),
                                             within: bounds)
        XCTAssertEqual(back.x, 110)
    }

    func testHitPicksNearestRoundItem() {
        let a = HoneycombLensGeometry.place(cell: .zero, at: .zero, viewSize: view, metrics: m)
        let b = HoneycombLensGeometry.place(cell: CGPoint(x: m.spacing, y: 0), at: .zero,
                                            viewSize: view, metrics: m)
        XCTAssertEqual(HoneycombLensGeometry.hit([(0, a), (1, b)], at: a.center), 0)
        XCTAssertEqual(HoneycombLensGeometry.hit([(0, a), (1, b)], at: b.center), 1)
        XCTAssertNil(HoneycombLensGeometry.hit([(0, a)], at: CGPoint(x: 0, y: 0)))
    }

    func testDragReleaseSettlesOnNearestAppAndSelectsIt() {
        let state = GridState()
        let lens = state.lens
        let ids = (0..<19).map { "app.\($0)" }
        lens.sync(ids: ids, metrics: m)
        XCTAssertEqual(state.selectedBundleID, "app.0")
        lens.drag(to: CGPoint(x: 500, y: 500))
        // Drag left by about one cell: the honeycomb moves right under the middle.
        lens.drag(to: CGPoint(x: 500 - m.spacing / m.panRatio, y: 500))
        XCTAssertFalse(lens.endDrag())
        let settled = ProcessInfo.processInfo.systemUptime + 2
        lens.advance(at: settled)
        guard let selected = state.selectedBundleID, let index = ids.firstIndex(of: selected) else {
            return XCTFail("no selection")
        }
        XCTAssertNotEqual(selected, "app.0")
        XCTAssertEqual(lens.at, lens.cells[index])
        lens.stop()
    }

    func testShortPressIsClick() {
        let state = GridState()
        state.lens.sync(ids: ["a", "b"], metrics: m)
        state.lens.drag(to: CGPoint(x: 10, y: 10))
        state.lens.drag(to: CGPoint(x: 11, y: 10))
        XCTAssertTrue(state.lens.endDrag())
    }

    func testResetClearsPan() {
        let state = GridState()
        state.lens.sync(ids: ["a", "b", "c"], metrics: m)
        state.lens.scroll(by: CGSize(width: 40, height: 0))
        state.resetViewport()
        XCTAssertEqual(state.lens.at, .zero)
        XCTAssertTrue(state.lens.cells.isEmpty)
    }
}
