import XCTest
@testable import HaloCore

/// Regression coverage for the "next slot lights up on summon" flash.
/// Before the fix, AppDelegate seeded `state.phase = .hovering(frontmostIdx)`
/// directly; the 1/60s cursor poll then cleared it back to `.idle`, and
/// the 0.14s sector animation in RadialView made the brief transition
/// visible as a flash on the frontmost slot — even when the user was
/// clicking somewhere else entirely. The fix routes the frontmost slot
/// through `scrollAnchor`, which only affects scroll routing — never the
/// rendered phase. These tests pin that routing in place.
final class SlotCycleTests: XCTestCase {
    func test_cursorHover_winsOverScrollAnchor() {
        // User has cursor on slot 2, scroll anchor (frontmost) is slot 5.
        // Scroll down → advance from hover (2), not anchor (5).
        let next = SlotCycle.nextIndex(
            delta: 1, slotCount: 8,
            currentHover: 2, scrollAnchor: 5
        )
        XCTAssertEqual(next, 3)
    }

    func test_scrollAnchor_seedsFirstScroll_whenNoHover() {
        // No cursor hover. Anchor = 5 (frontmost). Scroll down by 1.
        let next = SlotCycle.nextIndex(
            delta: 1, slotCount: 8,
            currentHover: nil, scrollAnchor: 5
        )
        XCTAssertEqual(next, 6)
    }

    func test_scrollAnchor_ignored_whenOutOfRange() {
        // Anchor 12 but slotCount shrunk to 8. Fall back to slot 0.
        let next = SlotCycle.nextIndex(
            delta: 1, slotCount: 8,
            currentHover: nil, scrollAnchor: 12
        )
        XCTAssertEqual(next, 1)
    }

    func test_scrollAnchor_ignored_atBoundary() {
        // Boundary: anchor == slotCount should be rejected (slots are
        // 0..<slotCount). Pre-fix the `< slotCount` check would have
        // been satisfied by `<=` and called 8 a valid index in an 8-slot
        // wheel, advancing into slot 9 (which doesn't exist).
        let next = SlotCycle.nextIndex(
            delta: 1, slotCount: 8,
            currentHover: nil, scrollAnchor: 8
        )
        XCTAssertEqual(next, 1, "anchor == slotCount must fall back to slot 0, advance to 1")
    }

    func test_scrollAnchor_negative_isAccepted_butWrapsCorrectly() {
        // Defensive: negative anchor isn't a normal value but math
        // shouldn't trap. Fallback via the `< slotCount` predicate; -1
        // satisfies it. Wrap-around modulo handles the rest.
        let next = SlotCycle.nextIndex(
            delta: 1, slotCount: 8,
            currentHover: nil, scrollAnchor: -1
        )
        // (-1 + 1) % 8 = 0 → 0
        XCTAssertEqual(next, 0)
    }

    func test_noHoverNoAnchor_anchorsToSlotZero() {
        let next = SlotCycle.nextIndex(
            delta: 1, slotCount: 8,
            currentHover: nil, scrollAnchor: nil
        )
        XCTAssertEqual(next, 1)
    }

    func test_negativeDelta_wrapsCounterClockwise() {
        let next = SlotCycle.nextIndex(
            delta: -1, slotCount: 8,
            currentHover: 0, scrollAnchor: nil
        )
        XCTAssertEqual(next, 7)
    }

    func test_consumesAnchor_onlyWhenAnchorIsUsed() {
        XCTAssertTrue(SlotCycle.consumedScrollAnchor(
            currentHover: nil, scrollAnchor: 5, slotCount: 8))
        XCTAssertFalse(SlotCycle.consumedScrollAnchor(
            currentHover: 2, scrollAnchor: 5, slotCount: 8))
        XCTAssertFalse(SlotCycle.consumedScrollAnchor(
            currentHover: nil, scrollAnchor: nil, slotCount: 8))
        XCTAssertFalse(SlotCycle.consumedScrollAnchor(
            currentHover: nil, scrollAnchor: 12, slotCount: 8))
    }
}
