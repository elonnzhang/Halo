import XCTest
@testable import HaloCore

@MainActor
final class AppPreferencesProfileTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let suite = "halo.prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    /// Seed v1.1.x legacy keys directly to simulate an upgrade.
    private func seedLegacyKeys(into defaults: UserDefaults) {
        defaults.set(10, forKey: "halo.prefs.slotCount")
        let pins: [String?] = ["com.apple.Terminal", nil, "com.microsoft.VSCode",
                               nil, nil, nil, nil, nil, nil, nil]
        defaults.set(try? JSONEncoder().encode(pins), forKey: "halo.prefs.pinnedSlots.v1")
        defaults.set(try? JSONEncoder().encode(["com.figma.Desktop"]),
                     forKey: "halo.prefs.overflowPins.v1")
    }

    // MARK: - Migration / first launch

    func test_firstLaunchFromBlankDefaults_createsOneDefaultProfile() {
        let prefs = AppPreferences(defaults: freshDefaults())
        XCTAssertEqual(prefs.profiles.count, 1)
        XCTAssertEqual(prefs.activeProfile.name, "Default")
        XCTAssertEqual(prefs.pinnedBundleIDs.count, 8)
        XCTAssertTrue(prefs.pinnedBundleIDs.allSatisfy { $0 == nil })
    }

    func test_legacyKeysMigrateIntoSingleDefaultProfile() {
        let defaults = freshDefaults()
        seedLegacyKeys(into: defaults)

        let prefs = AppPreferences(defaults: defaults)
        XCTAssertEqual(prefs.profiles.count, 1)
        let p = prefs.activeProfile
        XCTAssertEqual(p.name, "Default")
        XCTAssertEqual(p.pinnedBundleIDs.count, 10)
        XCTAssertEqual(p.pinnedBundleIDs[0], "com.apple.Terminal")
        XCTAssertEqual(p.pinnedBundleIDs[2], "com.microsoft.VSCode")
        XCTAssertEqual(p.overflowPinnedBundleIDs, ["com.figma.Desktop"])

        XCTAssertEqual(prefs.pinnedBundleIDs[0], "com.apple.Terminal")
        XCTAssertEqual(prefs.slotCount, 10)
    }

    func test_migrationIsIdempotent() {
        let defaults = freshDefaults()
        seedLegacyKeys(into: defaults)
        let firstID = AppPreferences(defaults: defaults).activeProfile.id
        let again = AppPreferences(defaults: defaults)
        XCTAssertEqual(again.profiles.count, 1)
        XCTAssertEqual(again.activeProfile.id, firstID)
    }

    // MARK: - Per-profile fields write through

    func test_setPinnedBundleID_writesThroughToActiveProfile() {
        let prefs = AppPreferences(defaults: freshDefaults())
        prefs.setPinnedBundleID("com.apple.Safari", at: 2)
        XCTAssertEqual(prefs.pinnedBundleIDs[2], "com.apple.Safari")
        XCTAssertEqual(prefs.activeProfile.pinnedBundleIDs[2], "com.apple.Safari")
    }

    func test_setIdentityOverride_writesActiveProfileOverrides() {
        let prefs = AppPreferences(defaults: freshDefaults())
        let color = IdentityColor(lightness: 0.6, chroma: 0.5, hue: 30)
        prefs.setIdentityOverride(color, for: "com.apple.Safari")
        XCTAssertEqual(prefs.identityOverride(for: "com.apple.Safari"), color)
        XCTAssertEqual(prefs.activeProfile.identityOverrides["com.apple.Safari"], color)

        prefs.setIdentityOverride(nil, for: "com.apple.Safari")
        XCTAssertNil(prefs.identityOverride(for: "com.apple.Safari"))
    }

    func test_clearAllBindings_clearsActiveProfileBindings() {
        let prefs = AppPreferences(defaults: freshDefaults())
        prefs.setPinnedBundleID("a", at: 0)
        prefs.setIdentityOverride(IdentityColor(lightness: 0.5, chroma: 0.1, hue: 1),
                                  for: "a")
        prefs.clearAllBindings()
        XCTAssertTrue(prefs.activeProfile.pinnedBundleIDs.allSatisfy { $0 == nil })
        XCTAssertTrue(prefs.activeProfile.identityOverrides.isEmpty)
    }

    // MARK: - slotCount is per-profile (v1.3 handoff alignment)

    func test_slotCountSet_writesToActiveProfile_andResizesPins() {
        let prefs = AppPreferences(defaults: freshDefaults())
        prefs.slotCount = 12
        XCTAssertEqual(prefs.slotCount, 12)
        XCTAssertEqual(prefs.activeProfile.slotCount, 12)
        XCTAssertEqual(prefs.activeProfile.pinnedBundleIDs.count, 12)

        // Setting again to a different value resizes again.
        prefs.slotCount = 6
        XCTAssertEqual(prefs.activeProfile.slotCount, 6)
        XCTAssertEqual(prefs.activeProfile.pinnedBundleIDs.count, 6)
    }

    func test_slotCountFollowsActiveProfile_acrossSwitches() {
        let prefs = AppPreferences(defaults: freshDefaults())
        let defaultID = prefs.activeProfileID
        prefs.slotCount = 10
        // Fresh profile inherits the current slot count so users don't
        // get yanked to a different wheel width on first creation.
        let work = prefs.addProfile(name: "Work", cloning: nil)
        XCTAssertEqual(work.slotCount, 10)
        // Edit Work to a different count.
        prefs.switchToProfile(work.id)
        prefs.slotCount = 6
        XCTAssertEqual(prefs.slotCount, 6)
        XCTAssertEqual(prefs.activeProfile.slotCount, 6)
        // Switching back to Default restores Default's slotCount, NOT
        // Work's — that's the new per-profile contract.
        prefs.switchToProfile(defaultID)
        XCTAssertEqual(prefs.slotCount, 10)
        XCTAssertEqual(prefs.activeProfile.slotCount, 10)
    }

    func test_cycleActiveProfile_wrapsAround() {
        let prefs = AppPreferences(defaults: freshDefaults())
        let defaultID = prefs.activeProfileID
        let a = prefs.addProfile(name: "A", cloning: nil)
        let b = prefs.addProfile(name: "B", cloning: nil)
        prefs.switchToProfile(defaultID)
        prefs.cycleActiveProfile(by: 1)
        XCTAssertEqual(prefs.activeProfileID, a.id)
        prefs.cycleActiveProfile(by: 1)
        XCTAssertEqual(prefs.activeProfileID, b.id)
        // Wrap forward.
        prefs.cycleActiveProfile(by: 1)
        XCTAssertEqual(prefs.activeProfileID, defaultID)
        // Wrap backward.
        prefs.cycleActiveProfile(by: -1)
        XCTAssertEqual(prefs.activeProfileID, b.id)
    }

    func test_setSlotCount_forNonActiveProfile_doesNotMutateActiveSlotCount() {
        let prefs = AppPreferences(defaults: freshDefaults())
        let defaultID = prefs.activeProfileID
        prefs.slotCount = 8
        let work = prefs.addProfile(name: "Work", cloning: nil)
        prefs.setSlotCount(12, for: work.id)
        // Default (still active) is unchanged.
        XCTAssertEqual(prefs.slotCount, 8)
        XCTAssertEqual(prefs.activeProfile.slotCount, 8)
        XCTAssertEqual(prefs.activeProfileID, defaultID)
        // Switching to Work shows the new size.
        prefs.switchToProfile(work.id)
        XCTAssertEqual(prefs.slotCount, 12)
        XCTAssertEqual(prefs.activeProfile.pinnedBundleIDs.count, 12)
    }

    func test_setTint_updatesProfileTint_andNilClears() {
        let prefs = AppPreferences(defaults: freshDefaults())
        let id = prefs.activeProfileID
        let blue = IdentityColor(lightness: 0.6, chroma: 0.2, hue: 240)
        prefs.setTint(blue, for: id)
        XCTAssertEqual(prefs.activeProfile.tint, blue)
        prefs.setTint(nil, for: id)
        XCTAssertNil(prefs.activeProfile.tint)
    }

    // MARK: - whitelist / ranking stay global

    func test_whitelistStaysGlobalAcrossProfileSwitches() {
        let prefs = AppPreferences(defaults: freshDefaults())
        prefs.whitelistedBundleIDs = ["com.valvesoftware.steam"]
        let work = prefs.addProfile(name: "Work", cloning: nil)
        prefs.switchToProfile(work.id)
        XCTAssertEqual(prefs.whitelistedBundleIDs, ["com.valvesoftware.steam"])
    }

    func test_frequencyProfileStaysGlobalAcrossProfileSwitches() {
        let prefs = AppPreferences(defaults: freshDefaults())
        prefs.frequencyProfile = .mfuOnly
        let work = prefs.addProfile(name: "Work", cloning: nil)
        prefs.switchToProfile(work.id)
        XCTAssertEqual(prefs.frequencyProfile, .mfuOnly)
    }

    // MARK: - Profile management API

    func test_addProfileBlank_appendsFresh() {
        let prefs = AppPreferences(defaults: freshDefaults())
        let p = prefs.addProfile(name: "Coding", cloning: nil)
        XCTAssertEqual(prefs.profiles.count, 2)
        XCTAssertEqual(p.name, "Coding")
        XCTAssertTrue(p.pinnedBundleIDs.allSatisfy { $0 == nil })
    }

    func test_addProfileCloningActive_deepCopiesBindings() {
        let prefs = AppPreferences(defaults: freshDefaults())
        prefs.setPinnedBundleID("com.apple.Safari", at: 0)
        let original = prefs.activeProfile
        let clone = prefs.addProfile(name: "Work", cloning: original.id)
        XCTAssertNotEqual(clone.id, original.id)
        XCTAssertEqual(clone.pinnedBundleIDs, original.pinnedBundleIDs)
    }

    func test_renameProfile_updatesName() {
        let prefs = AppPreferences(defaults: freshDefaults())
        let id = prefs.activeProfile.id
        prefs.renameProfile(id, to: "Home")
        XCTAssertEqual(prefs.activeProfile.name, "Home")
    }

    func test_switchToProfile_swapsPinProjection() {
        let prefs = AppPreferences(defaults: freshDefaults())
        prefs.setPinnedBundleID("com.apple.Safari", at: 0)
        let work = prefs.addProfile(name: "Work", cloning: nil)
        prefs.switchToProfile(work.id)
        XCTAssertEqual(prefs.activeProfileID, work.id)
        XCTAssertNil(prefs.pinnedBundleIDs[0])
    }

    func test_deleteActiveProfile_fallsBackToFirstRemaining() {
        let prefs = AppPreferences(defaults: freshDefaults())
        let secondID = prefs.addProfile(name: "Work", cloning: nil).id
        prefs.switchToProfile(secondID)
        prefs.deleteProfile(secondID)
        XCTAssertEqual(prefs.profiles.count, 1)
        XCTAssertEqual(prefs.activeProfile.name, "Default")
    }

    func test_deleteLastProfile_refusesAndLeavesStateIntact() {
        let prefs = AppPreferences(defaults: freshDefaults())
        let onlyID = prefs.activeProfile.id
        prefs.deleteProfile(onlyID)
        XCTAssertEqual(prefs.profiles.count, 1)
        XCTAssertEqual(prefs.activeProfile.id, onlyID)
    }

    func test_persistedProfilesSurviveRecreate() {
        let defaults = freshDefaults()
        do {
            let prefs = AppPreferences(defaults: defaults)
            _ = prefs.addProfile(name: "Coding", cloning: nil)
            _ = prefs.addProfile(name: "Meeting", cloning: nil)
            prefs.switchToProfile(prefs.profiles[1].id)
        }
        let prefs2 = AppPreferences(defaults: defaults)
        XCTAssertEqual(prefs2.profiles.map { $0.name },
                       ["Default", "Coding", "Meeting"])
        XCTAssertEqual(prefs2.activeProfile.name, "Coding")
    }
}
