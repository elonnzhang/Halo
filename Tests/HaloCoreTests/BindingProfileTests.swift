import XCTest
@testable import HaloCore

final class BindingProfileTests: XCTestCase {
    func test_freshDefault_hasEmptyBindings() {
        let p = BindingProfile.freshDefault()
        XCTAssertEqual(p.name, "Default")
        XCTAssertEqual(p.pinnedBundleIDs.count, 8)
        XCTAssertTrue(p.pinnedBundleIDs.allSatisfy { $0 == nil })
        XCTAssertTrue(p.overflowPinnedBundleIDs.isEmpty)
        XCTAssertTrue(p.identityOverrides.isEmpty)
    }

    func test_codable_roundTripPreservesAllFields() throws {
        var p = BindingProfile.freshDefault()
        p.name = "Coding"
        p.pinnedBundleIDs = Array(repeating: nil, count: 10)
        p.pinnedBundleIDs[0] = "com.apple.Terminal"
        p.pinnedBundleIDs[3] = "com.microsoft.VSCode"
        p.overflowPinnedBundleIDs = ["com.figma.Desktop"]
        p.identityOverrides = [
            "com.apple.Terminal": IdentityColor(lightness: 0.5, chroma: 0.4, hue: 200)
        ]

        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(BindingProfile.self, from: data)
        XCTAssertEqual(decoded, p)
    }

    func test_resizingSmaller_spillsTailPinsIntoOverflow() {
        var p = BindingProfile.freshDefault()
        p.pinnedBundleIDs[0] = "a"
        p.pinnedBundleIDs[5] = "f"
        p.pinnedBundleIDs[7] = "h"
        let smaller = p.resizing(slotCount: 6)
        XCTAssertEqual(smaller.pinnedBundleIDs.count, 6)
        XCTAssertEqual(smaller.pinnedBundleIDs[0], "a")
        XCTAssertEqual(smaller.pinnedBundleIDs[5], "f")
        XCTAssertEqual(smaller.overflowPinnedBundleIDs, ["h"])
    }

    func test_resizingLarger_replacesOverflowIntoLeadingEmptySlots() {
        var p = BindingProfile.freshDefault()
        p.pinnedBundleIDs = ["a", nil, "c", nil]
        p.overflowPinnedBundleIDs = ["e", "f"]
        let larger = p.resizing(slotCount: 8)
        XCTAssertEqual(larger.pinnedBundleIDs.count, 8)
        XCTAssertEqual(larger.pinnedBundleIDs[0], "a")
        XCTAssertEqual(larger.pinnedBundleIDs[1], "e")
        XCTAssertEqual(larger.pinnedBundleIDs[2], "c")
        XCTAssertEqual(larger.pinnedBundleIDs[3], "f")
        XCTAssertTrue(larger.pinnedBundleIDs[4..<8].allSatisfy { $0 == nil })
        XCTAssertTrue(larger.overflowPinnedBundleIDs.isEmpty)
    }

    func test_resizingToSameSize_isIdentity() {
        var p = BindingProfile.freshDefault()
        p.pinnedBundleIDs[3] = "x"
        let same = p.resizing(slotCount: 8)
        XCTAssertEqual(same, p)
    }

    func test_resizingClampsTo4Through12() {
        let p = BindingProfile.freshDefault()
        XCTAssertEqual(p.resizing(slotCount: 2).pinnedBundleIDs.count, 4)
        XCTAssertEqual(p.resizing(slotCount: 99).pinnedBundleIDs.count, 12)
    }
}
