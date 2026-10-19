import XCTest
@testable import HaloUI

final class FlowGeometryTests: XCTestCase {
    private func layout(
        _ widths: [CGFloat], height: CGFloat = 28, maxWidth: CGFloat,
        spacing: CGFloat = 8, lineSpacing: CGFloat = 6
    ) -> FlowGeometry.Result {
        FlowGeometry.layout(
            sizes: widths.map { CGSize(width: $0, height: height) },
            maxWidth: maxWidth, spacing: spacing, lineSpacing: lineSpacing)
    }

    func testEmptyInputHasNoSize() {
        let result = layout([], maxWidth: 300)
        XCTAssertTrue(result.frames.isEmpty)
        XCTAssertEqual(result.size, .zero)
    }

    func testItemsThatFitShareOneRow() {
        let result = layout([80, 60, 40], maxWidth: 300)
        XCTAssertEqual(result.frames.map(\.minX), [0, 88, 156])
        XCTAssertEqual(result.frames.map(\.minY), [0, 0, 0])
        XCTAssertEqual(result.size, CGSize(width: 196, height: 28))
    }

    func testWrapsWhenNextItemWouldOverflow() {
        // 100 + 8 + 100 = 208 > 200, so the second item starts a new row.
        let result = layout([100, 100, 60], maxWidth: 200)
        XCTAssertEqual(result.frames[0].origin, CGPoint(x: 0, y: 0))
        XCTAssertEqual(result.frames[1].origin, CGPoint(x: 0, y: 34))
        XCTAssertEqual(result.frames[2].origin, CGPoint(x: 108, y: 34))
        XCTAssertEqual(result.size, CGSize(width: 168, height: 62))
    }

    func testRowFittingExactlyIsNotWrapped() {
        let result = layout([96, 96], maxWidth: 200)
        XCTAssertEqual(result.frames.map(\.minY), [0, 0])
        XCTAssertEqual(result.size.width, 200)
    }

    func testOversizedItemIsClampedAndAlone() {
        let result = layout([40, 500, 40], maxWidth: 200)
        XCTAssertEqual(result.frames[1].width, 200)
        XCTAssertEqual(result.frames[0].minY, 0)
        XCTAssertEqual(result.frames[1].minY, 34)
        XCTAssertEqual(result.frames[1].minX, 0)
        XCTAssertEqual(result.frames[2].minY, 68)
    }

    func testRowHeightFollowsTallestItem() {
        let sizes = [CGSize(width: 50, height: 20), CGSize(width: 50, height: 40),
                     CGSize(width: 150, height: 10)]
        let result = FlowGeometry.layout(
            sizes: sizes, maxWidth: 120, spacing: 8, lineSpacing: 6)
        XCTAssertEqual(result.frames[2].minY, 46)
        XCTAssertEqual(result.size.height, 56)
    }

    func testUnboundedWidthKeepsOneRow() {
        let result = layout([300, 300, 300], maxWidth: .infinity)
        XCTAssertEqual(Set(result.frames.map(\.minY)), [0])
        XCTAssertEqual(result.size.width, 916)
    }

    func testZeroWidthPutsEachItemOnItsOwnRow() {
        let result = layout([40, 40, 40], maxWidth: 0)
        XCTAssertEqual(result.frames.map(\.minY), [0, 34, 68])
        XCTAssertEqual(result.size.height, 96)
    }

    func testFramesNeverOverlapAndStayInsideTheLimit() {
        let widths: [CGFloat] = (0..<40).map { CGFloat(30 + ($0 * 37) % 120) }
        let result = layout(widths, maxWidth: 360)
        for (index, frame) in result.frames.enumerated() {
            XCTAssertLessThanOrEqual(frame.maxX, 360.001)
            for other in result.frames[(index + 1)...] {
                XCTAssertFalse(frame.intersects(other))
            }
        }
    }

    func testNonFiniteItemSizesAreTreatedAsZero() {
        let result = FlowGeometry.layout(
            sizes: [CGSize(width: CGFloat.nan, height: 28), CGSize(width: 40, height: CGFloat.infinity)],
            maxWidth: 200, spacing: 8, lineSpacing: 6)
        XCTAssertEqual(result.frames[0].width, 0)
        XCTAssertEqual(result.frames[1].height, 0)
        XCTAssertTrue(result.size.width.isFinite && result.size.height.isFinite)
    }
}
