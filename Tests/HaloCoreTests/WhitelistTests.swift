import XCTest
@testable import HaloCore

@MainActor
final class WhitelistTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let suite = "halo.prefs.\(UUID().uuidString)"
        let d = UserDefaults(suiteName: suite)!
        d.removePersistentDomain(forName: suite)
        return d
    }

    func test_emptyByDefault() {
        let prefs = AppPreferences(defaults: freshDefaults())
        XCTAssertTrue(prefs.whitelistedBundleIDs.isEmpty)
        XCTAssertFalse(prefs.isHaloSuppressed(forFrontmost: "com.apple.dt.Xcode"))
    }

    func test_addingBundleID_suppresses() {
        let prefs = AppPreferences(defaults: freshDefaults())
        prefs.whitelistedBundleIDs = ["com.apple.dt.Xcode", "com.microsoft.VSCode"]
        XCTAssertTrue(prefs.isHaloSuppressed(forFrontmost: "com.apple.dt.Xcode"))
        XCTAssertTrue(prefs.isHaloSuppressed(forFrontmost: "com.microsoft.VSCode"))
        XCTAssertFalse(prefs.isHaloSuppressed(forFrontmost: "com.apple.Safari"))
        XCTAssertFalse(prefs.isHaloSuppressed(forFrontmost: nil))
    }

    func test_whitelistPersists() {
        let defaults = freshDefaults()
        let prefs = AppPreferences(defaults: defaults)
        prefs.whitelistedBundleIDs = ["org.blenderfoundation.blender"]
        let reloaded = AppPreferences(defaults: defaults)
        XCTAssertEqual(reloaded.whitelistedBundleIDs, ["org.blenderfoundation.blender"])
    }

    func test_dedupOnAssignment() {
        let prefs = AppPreferences(defaults: freshDefaults())
        prefs.whitelistedBundleIDs = ["a", "a", "b", "a"]
        XCTAssertEqual(prefs.whitelistedBundleIDs, ["a", "b"])
    }
}
