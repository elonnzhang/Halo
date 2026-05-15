import XCTest
@testable import HaloCore

final class ArcExecutorTests: XCTestCase {
    final class FakeArcRuntime: ArcRuntime, @unchecked Sendable {
        var quitBundleID: String?
        var hideBundleID: String?
        var fullscreenBundleID: String?
        var customExecuted: HaloAction?
        var customBundleID: String?
        var quitOK = true
        var hideOK = true
        var fullscreenOK = true
        var customOutcome: ActionOutcome = .executed

        func quit(bundleID: String) -> Bool {
            quitBundleID = bundleID; return quitOK
        }
        func hide(bundleID: String) -> Bool {
            hideBundleID = bundleID; return hideOK
        }
        func toggleFullscreen(bundleID: String) -> Bool {
            fullscreenBundleID = bundleID; return fullscreenOK
        }
        func executeCustom(_ action: HaloAction, forBundleID bundleID: String) -> ActionOutcome {
            customExecuted = action
            customBundleID = bundleID
            return customOutcome
        }
    }

    func test_quitChip_dispatchesQuit_andSurfacesFailure() {
        let fake = FakeArcRuntime()
        let exec = ArcExecutor(runtime: fake)
        XCTAssertEqual(exec.execute(chip: .builtin(.quit), forBundleID: "com.x"), .executed)
        XCTAssertEqual(fake.quitBundleID, "com.x")

        fake.quitOK = false
        XCTAssertEqual(exec.execute(chip: .builtin(.quit), forBundleID: "com.y"), .failed)
    }

    func test_hideChip_dispatchesHide() {
        let fake = FakeArcRuntime()
        let exec = ArcExecutor(runtime: fake)
        XCTAssertEqual(exec.execute(chip: .builtin(.hide), forBundleID: "com.x"), .executed)
        XCTAssertEqual(fake.hideBundleID, "com.x")
    }

    func test_fullscreenChip_dispatchesToggle() {
        let fake = FakeArcRuntime()
        let exec = ArcExecutor(runtime: fake)
        XCTAssertEqual(exec.execute(chip: .builtin(.fullscreenToggle), forBundleID: "com.x"), .executed)
        XCTAssertEqual(fake.fullscreenBundleID, "com.x")
    }

    func test_customChip_dispatchesAction_andForwardsBundleID() {
        let fake = FakeArcRuntime()
        let exec = ArcExecutor(runtime: fake)
        let a = HaloAction(label: "New Window", kind: .keyboardShortcut, payload: "cmd+n")
        XCTAssertEqual(exec.execute(chip: .custom(a), forBundleID: "com.x"), .executed)
        XCTAssertEqual(fake.customExecuted?.label, "New Window")
        XCTAssertEqual(fake.customBundleID, "com.x")
    }

    func test_emptyCustomChip_returnsExecutedNoOp() {
        let fake = FakeArcRuntime()
        let exec = ArcExecutor(runtime: fake)
        XCTAssertEqual(exec.execute(chip: .emptyCustom, forBundleID: "com.x"), .executed)
        XCTAssertNil(fake.customExecuted)
        XCTAssertNil(fake.quitBundleID)
    }

    func test_builtInActionKind_metadataIsStable() {
        XCTAssertTrue(BuiltInActionKind.fullscreenToggle.requiresAX)
        XCTAssertFalse(BuiltInActionKind.quit.requiresAX)
        XCTAssertFalse(BuiltInActionKind.hide.requiresAX)
        XCTAssertNotEqual(
            BuiltInActionKind.fullscreenToggle.sfSymbol,
            BuiltInActionKind.fullscreenToggle.sfSymbolAlt
        )
        XCTAssertEqual(
            BuiltInActionKind.quit.sfSymbol,
            BuiltInActionKind.quit.sfSymbolAlt
        )
    }
}
