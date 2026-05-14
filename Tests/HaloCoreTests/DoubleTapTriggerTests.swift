import XCTest
@testable import HaloCore

final class DoubleTapTriggerTests: XCTestCase {
    func test_allCases_haveDistinctLabels() {
        let labels = Set(DoubleTapTrigger.allCases.map(\.displayLabel))
        XCTAssertEqual(labels.count, DoubleTapTrigger.allCases.count)
    }

    func test_middleMouse_isOnlyNonKeyboard() {
        let nonKeyboard = DoubleTapTrigger.allCases.filter { !$0.isKeyboard }
        XCTAssertEqual(nonKeyboard, [.middleMouse])
    }

    func test_rawValuesRoundtrip() throws {
        for trigger in DoubleTapTrigger.allCases {
            let data = try JSONEncoder().encode(trigger)
            let decoded = try JSONDecoder().decode(DoubleTapTrigger.self, from: data)
            XCTAssertEqual(decoded, trigger)
        }
    }
}
