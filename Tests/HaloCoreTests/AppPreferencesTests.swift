import XCTest
@testable import HaloCore

@MainActor
final class AppPreferencesTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let suite = "halo.prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func test_defaultsMatchSpec_whenNothingPersisted() {
        let prefs = AppPreferences(defaults: freshDefaults())
        XCTAssertEqual(prefs.slotCount, 8)
        XCTAssertEqual(prefs.frequencyProfile, .balanced)
        XCTAssertEqual(prefs.summonPosition, .mouse)
        XCTAssertEqual(prefs.pinnedBundleIDs.count, 8)
        XCTAssertTrue(prefs.pinnedBundleIDs.allSatisfy { $0 == nil })
        XCTAssertEqual(prefs.hotkeyKeyCode, 49)         // Space
        XCTAssertEqual(prefs.hotkeyModifiers, [.command, .option])
        XCTAssertFalse(prefs.autostart)
    }

    func test_slotCount_clampedTo_4through12() {
        let prefs = AppPreferences(defaults: freshDefaults())
        prefs.slotCount = 3
        XCTAssertEqual(prefs.slotCount, 4)
        prefs.slotCount = 15
        XCTAssertEqual(prefs.slotCount, 12)
        prefs.slotCount = 6
        XCTAssertEqual(prefs.slotCount, 6)
    }

    func test_changingSlotCount_resizesPinArray_preservingLeadingPins() {
        let prefs = AppPreferences(defaults: freshDefaults())
        prefs.setPinnedBundleID("a.b.c", at: 0)
        prefs.setPinnedBundleID("d.e.f", at: 5)
        XCTAssertEqual(prefs.pinnedBundleIDs.count, 8)

        prefs.slotCount = 4
        XCTAssertEqual(prefs.pinnedBundleIDs.count, 4)
        XCTAssertEqual(prefs.pinnedBundleIDs[0], "a.b.c")
        // slot 5 drops off when we shrink to 4 — spec: "超出部分 Pin 保留但暂不显示"
        // We track these in overflowPinnedBundleIDs.
        XCTAssertTrue(prefs.overflowPinnedBundleIDs.contains("d.e.f"))

        prefs.slotCount = 8
        // Restored to first empty slot or to its original index when possible.
        XCTAssertEqual(prefs.pinnedBundleIDs.count, 8)
        XCTAssertEqual(prefs.pinnedBundleIDs[0], "a.b.c")
        XCTAssertTrue(prefs.pinnedBundleIDs.contains("d.e.f"))
    }

    func test_persistence_roundTripsAcrossInstances() {
        let defaults = freshDefaults()
        let prefs = AppPreferences(defaults: defaults)
        prefs.slotCount = 6
        prefs.frequencyProfile = .mfuOnly
        prefs.summonPosition = .center
        prefs.setPinnedBundleID("com.apple.Safari", at: 0)
        prefs.autostart = true
        prefs.hotkeyKeyCode = 36   // Return — arbitrary
        prefs.hotkeyModifiers = [.control]

        let reloaded = AppPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.slotCount, 6)
        XCTAssertEqual(reloaded.frequencyProfile, .mfuOnly)
        XCTAssertEqual(reloaded.summonPosition, .center)
        XCTAssertEqual(reloaded.pinnedBundleIDs[0], "com.apple.Safari")
        XCTAssertTrue(reloaded.autostart)
        XCTAssertEqual(reloaded.hotkeyKeyCode, 36)
        XCTAssertEqual(reloaded.hotkeyModifiers, [.control])
    }

    func test_identityColorOverride_persists() throws {
        let defaults = freshDefaults()
        let prefs = AppPreferences(defaults: defaults)
        let teal = IdentityColor(lightness: 0.7, chroma: 0.2, hue: 180)
        prefs.setIdentityOverride(teal, for: "com.example.app")

        let reloaded = AppPreferences(defaults: defaults)
        let restored = try XCTUnwrap(reloaded.identityOverride(for: "com.example.app"))
        XCTAssertEqual(restored.hue, 180, accuracy: 0.01)
        XCTAssertEqual(restored.chroma, 0.2, accuracy: 0.01)
    }

    func test_resetOnboarding_clearsFlag() {
        let defaults = freshDefaults()
        defaults.set(true, forKey: "halo.onboarding.shown")
        let prefs = AppPreferences(defaults: defaults)
        prefs.resetOnboarding()
        XCTAssertFalse(defaults.bool(forKey: "halo.onboarding.shown"))
    }

    // MARK: - v1.1 fields

    func test_navigationToggles_defaultToOn() {
        let prefs = AppPreferences(defaults: freshDefaults())
        XCTAssertTrue(prefs.scrollToSwitch)
        XCTAssertTrue(prefs.numberKeyCommit)
        XCTAssertTrue(prefs.highlightFrontmostOnSummon)
        XCTAssertTrue(prefs.soundEffectsEnabled)
    }

    func test_soundEffectsEnabled_persistsOffAcrossInstances() {
        let defaults = freshDefaults()
        let prefs = AppPreferences(defaults: defaults)
        prefs.soundEffectsEnabled = false
        let reloaded = AppPreferences(defaults: defaults)
        XCTAssertFalse(reloaded.soundEffectsEnabled)
    }

    func test_navigationToggles_persist() {
        let defaults = freshDefaults()
        let prefs = AppPreferences(defaults: defaults)
        prefs.scrollToSwitch = false
        prefs.numberKeyCommit = false
        prefs.highlightFrontmostOnSummon = false

        let reloaded = AppPreferences(defaults: defaults)
        XCTAssertFalse(reloaded.scrollToSwitch)
        XCTAssertFalse(reloaded.numberKeyCommit)
        XCTAssertFalse(reloaded.highlightFrontmostOnSummon)
    }

    func test_panelScale_defaultsToOne_andClamps() {
        let prefs = AppPreferences(defaults: freshDefaults())
        XCTAssertEqual(prefs.panelScale, 1.0, accuracy: 0.001)
        prefs.panelScale = 0.5
        XCTAssertEqual(prefs.panelScale, 0.80, accuracy: 0.001)
        prefs.panelScale = 2.0
        XCTAssertEqual(prefs.panelScale, 1.50, accuracy: 0.001)
        prefs.panelScale = 1.25
        XCTAssertEqual(prefs.panelScale, 1.25, accuracy: 0.001)
    }

    func test_resetLayout_clearsPanelScale() {
        let prefs = AppPreferences(defaults: freshDefaults())
        prefs.panelScale = 1.40
        prefs.resetLayout()
        XCTAssertEqual(prefs.panelScale, 1.0, accuracy: 0.001)
    }

    func test_doubleTapTrigger_defaultsToCommand_andPersists() {
        let defaults = freshDefaults()
        let prefs = AppPreferences(defaults: defaults)
        XCTAssertEqual(prefs.doubleTapTrigger, .command)
        prefs.doubleTapTrigger = .leftOption
        XCTAssertEqual(AppPreferences(defaults: defaults).doubleTapTrigger, .leftOption)
    }
}
