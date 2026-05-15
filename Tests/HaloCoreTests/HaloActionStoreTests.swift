import XCTest
@testable import HaloCore

@MainActor
final class HaloActionStoreTests: XCTestCase {
    private func freshDefaults() -> UserDefaults {
        let suite = "halo.prefs.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    func test_actions_emptyByDefault() {
        let prefs = AppPreferences(defaults: freshDefaults())
        XCTAssertTrue(prefs.actions(forBundleID: "com.apple.Finder").isEmpty)
        XCTAssertTrue(prefs.actionBoundBundleIDs.isEmpty)
    }

    func test_setActions_roundTrips() {
        let defaults = freshDefaults()
        let prefs = AppPreferences(defaults: defaults)
        let a1 = HaloAction(label: "Downloads", kind: .runShortcut, payload: "~/Downloads")
        let a2 = HaloAction(label: "GitHub", kind: .runShortcut, payload: "https://github.com")
        prefs.setActions([a1, a2], forBundleID: "com.apple.Finder")

        let reloaded = AppPreferences(defaults: defaults)
        let restored = reloaded.actions(forBundleID: "com.apple.Finder")
        XCTAssertEqual(restored.count, 2)
        XCTAssertEqual(restored[0].label, "Downloads")
        XCTAssertEqual(restored[0].kind, .runShortcut)
        XCTAssertEqual(restored[0].payload, "~/Downloads")
        XCTAssertEqual(restored[1].label, "GitHub")
        XCTAssertEqual(restored[1].kind, .runShortcut)
    }

    func test_setActions_emptyListClearsBundle() {
        let prefs = AppPreferences(defaults: freshDefaults())
        let a = HaloAction(label: "X", kind: .runShortcut, payload: "https://example.com")
        prefs.setActions([a], forBundleID: "com.x.y")
        XCTAssertEqual(prefs.actionBoundBundleIDs, ["com.x.y"])

        prefs.setActions([], forBundleID: "com.x.y")
        XCTAssertTrue(prefs.actionBoundBundleIDs.isEmpty)
        XCTAssertTrue(prefs.actions(forBundleID: "com.x.y").isEmpty)
    }

    func test_removeAction_preservesRemainingOrder() {
        let prefs = AppPreferences(defaults: freshDefaults())
        let a = HaloAction(label: "A", kind: .runShortcut, payload: "https://a")
        let b = HaloAction(label: "B", kind: .runShortcut, payload: "https://b")
        let c = HaloAction(label: "C", kind: .runShortcut, payload: "https://c")
        prefs.setActions([a, b, c], forBundleID: "x")

        prefs.removeAction(at: 1, forBundleID: "x")
        let after = prefs.actions(forBundleID: "x")
        XCTAssertEqual(after.map(\.label), ["A", "C"])
    }

    func test_removeLastAction_clearsBundleFromList() {
        let prefs = AppPreferences(defaults: freshDefaults())
        let a = HaloAction(label: "only", kind: .runShortcut, payload: "https://x")
        prefs.setActions([a], forBundleID: "z")
        prefs.removeAction(at: 0, forBundleID: "z")
        XCTAssertFalse(prefs.actionBoundBundleIDs.contains("z"))
    }

    func test_updateAction_replacesInPlace() {
        let prefs = AppPreferences(defaults: freshDefaults())
        let a = HaloAction(label: "old", kind: .runShortcut, payload: "https://old")
        prefs.setActions([a], forBundleID: "x")
        let replaced = HaloAction(id: a.id, label: "new", kind: .runShortcut, payload: "https://new")
        prefs.updateAction(replaced, at: 0, forBundleID: "x")
        let after = prefs.actions(forBundleID: "x")
        XCTAssertEqual(after.first?.label, "new")
        XCTAssertEqual(after.first?.payload, "https://new")
    }

    func test_outOfBoundsRemove_isNoOp() {
        let prefs = AppPreferences(defaults: freshDefaults())
        let a = HaloAction(label: "only", kind: .runShortcut, payload: "https://x")
        prefs.setActions([a], forBundleID: "x")
        prefs.removeAction(at: 5, forBundleID: "x")
        XCTAssertEqual(prefs.actions(forBundleID: "x").count, 1)
    }

    func test_actionEffectiveSymbol_fallsBackToKindDefault() {
        let a = HaloAction(label: "x", kind: .keyboardShortcut, payload: "cmd+n")
        XCTAssertEqual(a.effectiveSFSymbol, "keyboard")
        let b = HaloAction(label: "x", kind: .runShortcut, payload: "Daily", sfSymbol: "globe")
        XCTAssertEqual(b.effectiveSFSymbol, "globe")
        let c = HaloAction(label: "x", kind: .appleScript, payload: "say \"hi\"", sfSymbol: "")
        XCTAssertEqual(c.effectiveSFSymbol, "applescript")
    }
}
