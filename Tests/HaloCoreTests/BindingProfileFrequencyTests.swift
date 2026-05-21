import XCTest
@testable import HaloCore

final class BindingProfileFrequencyTests: XCTestCase {
    func test_freshDefault_hasBalancedFrequency() {
        let p = BindingProfile.freshDefault()
        XCTAssertEqual(p.frequencyProfile, .balanced)
    }

    func test_codable_roundTripPreservesFrequency() throws {
        var p = BindingProfile.freshDefault()
        p.frequencyProfile = .mruOnly

        let data = try JSONEncoder().encode(p)
        let decoded = try JSONDecoder().decode(BindingProfile.self, from: data)
        XCTAssertEqual(decoded.frequencyProfile, .mruOnly)
        XCTAssertEqual(decoded, p)
    }

    func test_decoder_missingFrequencyKey_fallsBackToBalanced() throws {
        // Synthesise a v1.2-shaped JSON (no `frequencyProfile` key) and
        // confirm the custom decoder defaults to `.balanced`.
        let id = UUID()
        let json = """
        {
          "id": "\(id.uuidString)",
          "name": "Legacy",
          "pinnedBundleIDs": [null, null, null, null, null, null, null, null],
          "overflowPinnedBundleIDs": [],
          "identityOverrides": {}
        }
        """
        let data = Data(json.utf8)
        let decoded = try JSONDecoder().decode(BindingProfile.self, from: data)
        XCTAssertEqual(decoded.frequencyProfile, .balanced)
        XCTAssertEqual(decoded.id, id)
        XCTAssertEqual(decoded.name, "Legacy")
    }

    func test_explicitFrequency_survivesEncoding() throws {
        let p = BindingProfile(
            name: "MFU profile",
            pinnedBundleIDs: Array(repeating: nil, count: 6),
            slotCount: 6,
            frequencyProfile: .mfuOnly
        )
        let data = try JSONEncoder().encode(p)
        // Confirm the key is actually present in the JSON, not just
        // synthesised by the decoder fallback.
        guard let json = String(data: data, encoding: .utf8) else {
            XCTFail("encoded JSON not UTF-8")
            return
        }
        XCTAssertTrue(json.contains("frequencyProfile"), "encoded JSON missing frequencyProfile key: \(json)")
        XCTAssertTrue(json.contains("mfuOnly"), "encoded JSON missing mfuOnly value: \(json)")
    }
}
