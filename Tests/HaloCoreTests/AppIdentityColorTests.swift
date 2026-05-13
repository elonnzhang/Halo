import XCTest
@testable import HaloCore

final class AppIdentityColorTests: XCTestCase {

    // MARK: - OKLCH round-trip

    func test_oklch_roundTripsPureRedThroughOKLab() {
        let red = IdentityColor.fromSRGB(r: 1.0, g: 0.0, b: 0.0)
        // Pure sRGB red lands near oklch(62.8% 0.258 29.2°)
        XCTAssertEqual(red.lightness, 0.628, accuracy: 0.01)
        XCTAssertEqual(red.chroma, 0.258, accuracy: 0.01)
        XCTAssertEqual(red.hue, 29.2, accuracy: 1.0)
    }

    func test_oklch_handlesPureBlue() {
        let blue = IdentityColor.fromSRGB(r: 0.0, g: 0.0, b: 1.0)
        XCTAssertEqual(blue.lightness, 0.452, accuracy: 0.01)
        XCTAssertEqual(blue.hue, 264.0, accuracy: 1.5)
    }

    // MARK: - Resolver: candidate handling

    func test_resolver_nilCandidateBecomesNeutralChroma() {
        // v1.1: nil candidates (extractor failed / empty slot) collapse to a
        // chroma-0 neutral instead of borrowing from a palette. The wheel
        // never shows a colour the app didn't earn from its own icon.
        let resolver = IdentityConflictResolver()
        let resolved = resolver.resolve(
            candidates: [nil, nil, nil, nil],
            usageOrder: [0, 1, 2, 3],
            n: 4
        )
        for color in resolved {
            XCTAssertEqual(color.chroma, 0.0, accuracy: 0.001,
                           "nil candidate should produce chroma-0 neutral, got \(color)")
        }
    }

    func test_resolver_lowChromaCandidateIsPreserved() {
        // v1.1: extractor results pass through untouched, even when their
        // chroma is below the old 0.12 floor — pastel-gradient apps (Dia,
        // Notion light theme, …) now show their actual faint tint instead
        // of being hijacked by a Hue-8 fallback slot colour.
        let pastel = IdentityColor(lightness: 0.7, chroma: 0.05, hue: 50)
        let resolver = IdentityConflictResolver()
        let resolved = resolver.resolve(
            candidates: [pastel, nil, nil, nil],
            usageOrder: [0, 1, 2, 3],
            n: 4
        )
        XCTAssertEqual(resolved[0].chroma, 0.05, accuracy: 0.001,
                       "low-chroma candidate must be kept, not replaced")
        XCTAssertEqual(resolved[0].hue, 50, accuracy: 0.5)
    }

    // MARK: - Resolver: conflict push

    func test_resolver_conflictPushesLowerFrequencyHue() {
        // N=8 → threshold 360/8 * 0.6 = 27°
        // slot 0 = 45° (high-freq), slot 1 = 55° (low-freq, conflict)
        let highFreq = IdentityColor(lightness: 0.7, chroma: 0.2, hue: 45)
        let lowFreq  = IdentityColor(lightness: 0.7, chroma: 0.2, hue: 55)
        let resolver = IdentityConflictResolver()

        let resolved = resolver.resolve(
            candidates: [highFreq, lowFreq, nil, nil, nil, nil, nil, nil],
            usageOrder: [0, 1, 2, 3, 4, 5, 6, 7], // slot 0 has higher frequency
            n: 8
        )

        XCTAssertEqual(resolved[0].hue, 45, accuracy: 0.01,
                       "high-frequency slot should keep its original hue")
        // push by 360/N * 0.4 = 18°  → 55 + 18 = 73
        XCTAssertEqual(resolved[1].hue, 73, accuracy: 0.5,
                       "low-frequency conflicting slot should be pushed by 360°/N × 0.4 = 18°")
    }

    func test_resolver_nonConflictingHuesArePreserved() {
        // 70° apart at N=8 (threshold 27°) → safe
        let a = IdentityColor(lightness: 0.7, chroma: 0.2, hue: 100)
        let b = IdentityColor(lightness: 0.7, chroma: 0.2, hue: 170)
        let resolver = IdentityConflictResolver()

        let resolved = resolver.resolve(
            candidates: [a, b, nil, nil, nil, nil, nil, nil],
            usageOrder: [0, 1, 2, 3, 4, 5, 6, 7],
            n: 8
        )

        XCTAssertEqual(resolved[0].hue, 100, accuracy: 0.01)
        XCTAssertEqual(resolved[1].hue, 170, accuracy: 0.01)
    }

    func test_resolver_pushIsCappedAtOnePerPass_evenAgainstChainOfNeighbours() {
        // Regression: previously a single slot could chain N-1 +pushAmount
        // shifts in one resolve pass, taking a green icon (~145°) all the way
        // to pink (~321°). Cap is one push per pass.
        let target = IdentityColor(lightness: 0.7, chroma: 0.2, hue: 195)
        let neighbours = stride(from: 200.0, through: 290.0, by: 15.0).map {
            IdentityColor(lightness: 0.7, chroma: 0.2, hue: $0)
        }
        let candidates: [IdentityColor?] = neighbours.map { $0 } + [target]
        let resolver = IdentityConflictResolver()

        let resolved = resolver.resolve(
            candidates: candidates,
            usageOrder: Array(0..<8),
            n: 8
        )

        // Capped: target shifts by at most one pushAmount (18° at N=8).
        XCTAssertEqual(resolved[7].hue, 213, accuracy: 0.5,
                       "low-frequency slot should be pushed by exactly one pushAmount, not cascade")
    }

    func test_resolver_neutralSlotsDoNotParticipateInConflict() {
        // A chroma-0 neutral has no hue identity; it must not trigger pushes
        // for or against itself.
        let coloured = IdentityColor(lightness: 0.7, chroma: 0.2, hue: 10)
        let resolver = IdentityConflictResolver()
        let resolved = resolver.resolve(
            candidates: [nil, coloured, nil, nil],
            usageOrder: [0, 1, 2, 3],
            n: 4
        )
        XCTAssertEqual(resolved[1].hue, 10, accuracy: 0.01,
                       "coloured slot must not be pushed by neutral neighbours")
        XCTAssertEqual(resolved[0].chroma, 0, accuracy: 0.001)
        XCTAssertEqual(resolved[2].chroma, 0, accuracy: 0.001)
        XCTAssertEqual(resolved[3].chroma, 0, accuracy: 0.001)
    }
}
