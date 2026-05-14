import XCTest
@testable import HaloCore

/// Layout-related clamp + bounds tests for `AppPreferences`. The base
/// test file `AppPreferencesTests.swift` covers happy-path persistence;
/// these focus on the auto-clamp-on-read behaviour that protects the
/// renderer from stored values that would draw off-screen.
@MainActor
final class AppPreferencesBoundsTests: XCTestCase {

    private func freshDefaults() -> UserDefaults {
        let suite = "halo.prefs.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    // MARK: haloDiameter

    func test_haloDiameter_defaults_andClamps() {
        let prefs = AppPreferences(defaults: freshDefaults())
        XCTAssertEqual(prefs.haloDiameter, AppPreferences.defaultHaloDiameter)
        prefs.haloDiameter = 100   // below 280 floor
        XCTAssertEqual(prefs.haloDiameter, 280)
        prefs.haloDiameter = 1000  // above 440 ceiling
        XCTAssertEqual(prefs.haloDiameter, 440)
        prefs.haloDiameter = 320
        XCTAssertEqual(prefs.haloDiameter, 320)
    }

    // MARK: iconSize

    func test_iconSize_defaults_andClamps() {
        let prefs = AppPreferences(defaults: freshDefaults())
        XCTAssertEqual(prefs.iconSize, AppPreferences.defaultIconSize)
        prefs.iconSize = 0
        XCTAssertEqual(prefs.iconSize, 36)
        prefs.iconSize = 200
        XCTAssertEqual(prefs.iconSize, 64)
    }

    // MARK: iconRadius / iconRadiusBounds

    func test_iconRadius_clampedToBoundsOnRead() {
        let prefs = AppPreferences(defaults: freshDefaults())
        let bounds = prefs.iconRadiusBounds
        prefs.iconRadius = bounds.min - 50
        XCTAssertEqual(prefs.iconRadius, bounds.min, accuracy: 0.01)
        prefs.iconRadius = bounds.max + 50
        XCTAssertEqual(prefs.iconRadius, bounds.max, accuracy: 0.01)
    }

    func test_iconRadiusBounds_shrinkWhenHaloShrinks() {
        let prefs = AppPreferences(defaults: freshDefaults())
        prefs.haloDiameter = 440
        let wideBounds = prefs.iconRadiusBounds
        prefs.haloDiameter = 280
        let narrowBounds = prefs.iconRadiusBounds
        XCTAssertLessThan(narrowBounds.max, wideBounds.max)
    }

    // MARK: cmdDoubleTapGap clamp

    func test_cmdDoubleTapGap_clamps() {
        let prefs = AppPreferences(defaults: freshDefaults())
        prefs.cmdDoubleTapGap = 0.05
        XCTAssertEqual(prefs.cmdDoubleTapGap, 0.15, accuracy: 0.001)
        prefs.cmdDoubleTapGap = 1.50
        XCTAssertEqual(prefs.cmdDoubleTapGap, 0.50, accuracy: 0.001)
        prefs.cmdDoubleTapGap = 0.32
        XCTAssertEqual(prefs.cmdDoubleTapGap, 0.32, accuracy: 0.001)
    }

    // MARK: clearAllBindings

    func test_clearAllBindings_resetsPinsAndOverrides() {
        let prefs = AppPreferences(defaults: freshDefaults())
        prefs.setPinnedBundleID("com.apple.Safari", at: 0)
        prefs.setPinnedBundleID("com.apple.Notes", at: 1)
        let teal = IdentityColor(lightness: 0.7, chroma: 0.2, hue: 180)
        prefs.setIdentityOverride(teal, for: "com.apple.Safari")

        prefs.clearAllBindings()

        XCTAssertTrue(prefs.pinnedBundleIDs.allSatisfy { $0 == nil })
        XCTAssertNil(prefs.identityOverride(for: "com.apple.Safari"))
    }

    // MARK: appLanguageOverride mirrors AppleLanguages

    func test_appLanguageOverride_mirrorsAppleLanguages() {
        let defaults = freshDefaults()
        let prefs = AppPreferences(defaults: defaults)
        prefs.appLanguageOverride = "zh-Hans"
        XCTAssertEqual(defaults.array(forKey: "AppleLanguages") as? [String], ["zh-Hans"])

        prefs.appLanguageOverride = nil
        // After clearing the override the prefs accessor itself should
        // be nil. NB: `defaults.array(forKey: "AppleLanguages")` can
        // still return system inheritance fallback, so we test the
        // prefs surface (not the raw default) here.
        XCTAssertNil(prefs.appLanguageOverride)
    }

    // MARK: identity override deletion

    func test_setIdentityOverride_nil_removesEntry() {
        let prefs = AppPreferences(defaults: freshDefaults())
        let teal = IdentityColor(lightness: 0.7, chroma: 0.2, hue: 180)
        prefs.setIdentityOverride(teal, for: "com.example.app")
        XCTAssertNotNil(prefs.identityOverride(for: "com.example.app"))
        prefs.setIdentityOverride(nil, for: "com.example.app")
        XCTAssertNil(prefs.identityOverride(for: "com.example.app"))
    }

    // MARK: resizePinned position preservation

    func test_resizePinned_restoresOverflowToFirstEmpty() {
        let prefs = AppPreferences(defaults: freshDefaults())
        prefs.setPinnedBundleID("a", at: 0)
        prefs.setPinnedBundleID("b", at: 3)
        prefs.setPinnedBundleID("c", at: 7)

        prefs.slotCount = 4   // c overflows
        XCTAssertEqual(prefs.pinnedBundleIDs.count, 4)
        XCTAssertEqual(prefs.pinnedBundleIDs[0], "a")
        XCTAssertEqual(prefs.pinnedBundleIDs[3], "b")
        XCTAssertTrue(prefs.overflowPinnedBundleIDs.contains("c"))

        prefs.slotCount = 8   // c flows back to first empty (1)
        XCTAssertEqual(prefs.pinnedBundleIDs.count, 8)
        XCTAssertEqual(prefs.pinnedBundleIDs[0], "a")
        XCTAssertEqual(prefs.pinnedBundleIDs[3], "b")
        XCTAssertEqual(prefs.pinnedBundleIDs[1], "c", "first empty should adopt overflowed pin")
    }
}
