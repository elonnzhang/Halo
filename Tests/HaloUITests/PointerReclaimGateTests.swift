import XCTest
import CoreGraphics
@testable import HaloUI

final class PointerReclaimGateTests: XCTestCase {
    private func point(_ x: CGFloat, _ y: CGFloat = 0) -> CGPoint { CGPoint(x: x, y: y) }

    func test_pointerAlwaysDrives_whenInputDoesNotOwnTheSelection() {
        var gate = PointerReclaimGate()
        XCTAssertTrue(gate.pointerMoved(to: point(10), inputOwnsSelection: false, generation: 0))
        XCTAssertTrue(gate.pointerMoved(to: point(10), inputOwnsSelection: false, generation: 0))
    }

    func test_parkedCursor_doesNotReclaim() {
        var gate = PointerReclaimGate()
        XCTAssertFalse(gate.pointerMoved(to: point(100, 100), inputOwnsSelection: true, generation: 1))
        XCTAssertFalse(gate.pointerMoved(to: point(100, 100), inputOwnsSelection: true, generation: 1))
    }

    func test_jitterBelowTheThreshold_doesNotReclaim() {
        var gate = PointerReclaimGate()
        XCTAssertFalse(gate.pointerMoved(to: point(0), inputOwnsSelection: true, generation: 1))
        XCTAssertFalse(gate.pointerMoved(to: point(1, 1), inputOwnsSelection: true, generation: 1))
        XCTAssertFalse(gate.pointerMoved(to: point(-2, 1), inputOwnsSelection: true, generation: 1))
    }

    func test_movementAtTheThreshold_reclaims() {
        var gate = PointerReclaimGate()
        XCTAssertFalse(gate.pointerMoved(to: point(0), inputOwnsSelection: true, generation: 1))
        XCTAssertFalse(gate.pointerMoved(to: point(PointerReclaimGate.reclaimDistance - 0.5),
                                         inputOwnsSelection: true, generation: 1))
        XCTAssertTrue(gate.pointerMoved(to: point(PointerReclaimGate.reclaimDistance),
                                        inputOwnsSelection: true, generation: 1))
    }

    func test_slowDriftAccumulatesAgainstTheBaseline() {
        var gate = PointerReclaimGate()
        var moved = false
        for step in 0...10 {
            moved = gate.pointerMoved(to: point(CGFloat(step) * 0.5), inputOwnsSelection: true, generation: 1)
            if moved { break }
        }
        XCTAssertTrue(moved, "0.5pt per sample must eventually add up to a real move")
    }

    func test_baselineStartsOverWhenOwnershipEndsAndReturns() {
        var gate = PointerReclaimGate()
        XCTAssertFalse(gate.pointerMoved(to: point(0), inputOwnsSelection: true, generation: 1))
        XCTAssertTrue(gate.pointerMoved(to: point(50), inputOwnsSelection: false, generation: 1))
        XCTAssertFalse(gate.pointerMoved(to: point(50), inputOwnsSelection: true, generation: 2),
                       "a new takeover measures from where the cursor is now, not from the old baseline")
    }

    func test_eachInputStep_measuresFromTheCursorAtThatStep() {
        var gate = PointerReclaimGate()
        // 2pt of drift between successive wheel steps is jitter, not a takeover,
        // however many steps the user scrolls through.
        for step in 1...6 {
            XCTAssertFalse(gate.pointerMoved(to: point(CGFloat(step) * 2), inputOwnsSelection: true,
                                             generation: UInt(step)),
                           "step \(step) must re-measure from the cursor at that step")
        }
    }

    func test_stepRightAfterAReclaim_doesNotReuseTheOldBaseline() {
        var gate = PointerReclaimGate()
        XCTAssertFalse(gate.pointerMoved(to: point(0), inputOwnsSelection: true, generation: 1))
        XCTAssertTrue(gate.pointerMoved(to: point(10), inputOwnsSelection: true, generation: 1))
        // The wheel took the highlight back before the poll ever saw the pointer
        // owning it, so no unowned sample cleared the baseline in between.
        XCTAssertFalse(gate.pointerMoved(to: point(10), inputOwnsSelection: true, generation: 2),
                       "the parked cursor must not undo a step taken right after the pointer reclaimed")
        XCTAssertTrue(gate.pointerMoved(to: point(10 + PointerReclaimGate.reclaimDistance),
                                        inputOwnsSelection: true, generation: 2))
    }
}
