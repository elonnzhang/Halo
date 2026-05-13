import XCTest
@testable import HaloCore

final class AppIdentityColorTests: XCTestCase {
    func test_fallbackPalette_baseHueIs230_andSpansEqualArcs() {
        let palette = IdentityPalette.fallback(n: 8)
        XCTAssertEqual(palette.count, 8)
        XCTAssertEqual(palette[0].hue, 230, accuracy: 0.01)
        XCTAssertEqual(palette[1].hue, 230 + 45, accuracy: 0.01)
        XCTAssertEqual(palette[2].hue, 230 + 90, accuracy: 0.01)
        // wraps past 360
        XCTAssertEqual(palette[4].hue, (230 + 180).truncatingRemainder(dividingBy: 360), accuracy: 0.01)
    }

    func test_fallbackPalette_supportsAllNInRange() {
        for n in 4...12 {
            let palette = IdentityPalette.fallback(n: n)
            XCTAssertEqual(palette.count, n, "n=\(n) should produce n entries")
            for color in palette {
                XCTAssertEqual(color.lightness, 0.65, accuracy: 0.001)
                XCTAssertEqual(color.chroma, 0.18, accuracy: 0.001)
            }
        }
    }

    func test_n8FallbackRestoresHuePalette_whenRequested() {
        let palette = IdentityPalette.hue8()
        XCTAssertEqual(palette.count, 8)
        // Spot-check three of the locked Hue colors per VISUAL §4.2
        // slot 0: aqua oklch(70% 0.13 230)
        XCTAssertEqual(palette[0].hue, 230, accuracy: 1.0)
        XCTAssertEqual(palette[0].lightness, 0.70, accuracy: 0.01)
        // slot 3: pink oklch(58% 0.24 5)
        XCTAssertEqual(palette[3].hue, 5, accuracy: 1.0)
        // slot 7: green oklch(67% 0.18 145)
        XCTAssertEqual(palette[7].hue, 145, accuracy: 1.0)
    }

    func test_resolver_lowSaturationFallsBackToPaletteSlot() {
        // Greyscale candidate at slot 2; should be replaced by fallback[2].
        let grey = IdentityColor(lightness: 0.5, chroma: 0.05, hue: 200) // chroma < 0.12 threshold
        let resolver = IdentityConflictResolver()

        let resolved = resolver.resolve(
            candidates: [nil, nil, grey, nil],
            usageOrder: [0, 1, 2, 3],
            n: 4,
            useHue8: false
        )

        let fallback = IdentityPalette.fallback(n: 4)
        XCTAssertEqual(resolved[2].hue, fallback[2].hue, accuracy: 0.01,
                       "low-saturation icon color should be replaced by slot fallback")
    }

    func test_resolver_conflictPushesLowerFrequencyHue() {
        // N=8 → threshold 360/8 * 0.6 = 27°
        // slot 0 = 45° (high-freq), slot 1 = 55° (low-freq, conflict)
        let highFreq = IdentityColor(lightness: 0.7, chroma: 0.2, hue: 45)
        let lowFreq = IdentityColor(lightness: 0.7, chroma: 0.2, hue: 55)
        let resolver = IdentityConflictResolver()

        let resolved = resolver.resolve(
            candidates: [highFreq, lowFreq, nil, nil, nil, nil, nil, nil],
            usageOrder: [0, 1, 2, 3, 4, 5, 6, 7], // slot 0 has higher frequency
            n: 8,
            useHue8: false
        )

        XCTAssertEqual(resolved[0].hue, 45, accuracy: 0.01,
                       "high-frequency slot should keep its original hue")
        // push by 360/N * 0.4 = 18°  → 55 + 18 = 73
        XCTAssertEqual(resolved[1].hue, 73, accuracy: 0.5,
                       "low-frequency conflicting slot should be pushed by 360°/N × 0.4 = 18°")
    }

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

    func test_resolver_nonConflictingHuesArePreserved() {
        // 70° apart at N=8 (threshold 27°) → safe
        let a = IdentityColor(lightness: 0.7, chroma: 0.2, hue: 100)
        let b = IdentityColor(lightness: 0.7, chroma: 0.2, hue: 170)
        let resolver = IdentityConflictResolver()

        let resolved = resolver.resolve(
            candidates: [a, b, nil, nil, nil, nil, nil, nil],
            usageOrder: [0, 1, 2, 3, 4, 5, 6, 7],
            n: 8,
            useHue8: false
        )

        XCTAssertEqual(resolved[0].hue, 100, accuracy: 0.01)
        XCTAssertEqual(resolved[1].hue, 170, accuracy: 0.01)
    }

    func test_resolver_pushIsCappedAtOnePerPass_evenAgainstChainOfNeighbours() {
        // Regression: previously a single slot could chain N-1 +pushAmount
        // shifts in one resolve pass, taking a green icon (~145°) all the way
        // to pink (~321°). Cap is one push per pass.
        let target = IdentityColor(lightness: 0.7, chroma: 0.2, hue: 195)
        // Seven previous slots clustered around 200..290° — with the old
        // unbounded loop the target would cascade through every one.
        let neighbours = stride(from: 200.0, through: 290.0, by: 15.0).map {
            IdentityColor(lightness: 0.7, chroma: 0.2, hue: $0)
        }
        let candidates: [IdentityColor?] = neighbours.map { $0 } + [target]
        let resolver = IdentityConflictResolver()

        let resolved = resolver.resolve(
            candidates: candidates,
            usageOrder: Array(0..<8),
            n: 8,
            useHue8: false
        )

        // Capped: target shifts by at most one pushAmount (18° at N=8).
        XCTAssertEqual(resolved[7].hue, 213, accuracy: 0.5,
                       "low-frequency slot should be pushed by exactly one pushAmount, not cascade")
    }
}
