import XCTest
@testable import HaloCore

final class ActionExecutorTests: XCTestCase {
    final class FakeRuntime: ActionRuntime, @unchecked Sendable {
        var openedURL: URL?
        var postedShortcut: KeyboardShortcut?
        var postedToBundleID: String?
        var executedScript: String?
        var openShouldSucceed = true
        var postShouldSucceed = true
        var scriptShouldSucceed = true

        func openURL(_ url: URL) -> Bool {
            openedURL = url
            return openShouldSucceed
        }
        func postKeystroke(_ shortcut: KeyboardShortcut, toBundleID bundleID: String) -> Bool {
            postedShortcut = shortcut
            postedToBundleID = bundleID
            return postShouldSucceed
        }
        func runAppleScript(_ source: String) -> Bool {
            executedScript = source
            return scriptShouldSucceed
        }
    }

    // MARK: - Keyboard shortcut

    func test_keyboardShortcut_parsesAndPostsToBundle() {
        let fake = FakeRuntime()
        let exec = ActionExecutor(runtime: fake)
        let action = HaloAction(label: "New Window", kind: .keyboardShortcut, payload: "cmd+n")
        XCTAssertEqual(exec.execute(action, forBundleID: "com.x"), .executed)
        XCTAssertEqual(fake.postedToBundleID, "com.x")
        XCTAssertEqual(fake.postedShortcut?.keyCode, 45)         // n
        XCTAssertEqual(fake.postedShortcut?.modifierMask, 0x100000) // command
    }

    func test_keyboardShortcut_failsWhenPayloadUnparseable() {
        let fake = FakeRuntime()
        let exec = ActionExecutor(runtime: fake)
        let action = HaloAction(label: "x", kind: .keyboardShortcut, payload: "cmd+yodelay")
        XCTAssertEqual(exec.execute(action, forBundleID: "com.x"), .failed)
        XCTAssertNil(fake.postedShortcut)
    }

    func test_keyboardShortcut_runtimeFailureBubblesUp() {
        let fake = FakeRuntime()
        fake.postShouldSucceed = false
        let exec = ActionExecutor(runtime: fake)
        XCTAssertEqual(
            exec.execute(
                HaloAction(label: "x", kind: .keyboardShortcut, payload: "cmd+n"),
                forBundleID: "com.x"
            ),
            .failed
        )
    }

    // MARK: - Run Shortcut (URL scheme)

    func test_runShortcut_buildsShortcutsURL_andRoutesToOpenURL() throws {
        let fake = FakeRuntime()
        let exec = ActionExecutor(runtime: fake)
        let result = exec.execute(
            HaloAction(label: "x", kind: .runShortcut, payload: "Daily Build & Ship"),
            forBundleID: "com.x"
        )
        XCTAssertEqual(result, .executed)
        let url = try XCTUnwrap(fake.openedURL)
        let comps = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(comps.scheme, "shortcuts")
        XCTAssertEqual(comps.host, "run-shortcut")
        XCTAssertEqual(
            comps.queryItems?.first { $0.name == "name" }?.value,
            "Daily Build & Ship"
        )
    }

    func test_runShortcut_emptyName_failsBeforeOpen() {
        let fake = FakeRuntime()
        let exec = ActionExecutor(runtime: fake)
        XCTAssertEqual(
            exec.execute(
                HaloAction(label: "x", kind: .runShortcut, payload: "   "),
                forBundleID: "com.x"
            ),
            .failed
        )
        XCTAssertNil(fake.openedURL)
    }

    // MARK: - AppleScript

    func test_appleScript_forwardsTrimmedSource() {
        let fake = FakeRuntime()
        let exec = ActionExecutor(runtime: fake)
        let action = HaloAction(
            label: "Activate Finder",
            kind: .appleScript,
            payload: "  tell application \"Finder\" to activate  \n"
        )
        XCTAssertEqual(exec.execute(action, forBundleID: "com.apple.finder"), .executed)
        XCTAssertEqual(fake.executedScript, "tell application \"Finder\" to activate")
    }

    func test_appleScript_emptySource_fails() {
        let fake = FakeRuntime()
        let exec = ActionExecutor(runtime: fake)
        XCTAssertEqual(
            exec.execute(
                HaloAction(label: "x", kind: .appleScript, payload: ""),
                forBundleID: "x"
            ),
            .failed
        )
        XCTAssertNil(fake.executedScript)
    }

    func test_appleScript_runtimeFailure_bubblesUp() {
        let fake = FakeRuntime()
        fake.scriptShouldSucceed = false
        let exec = ActionExecutor(runtime: fake)
        XCTAssertEqual(
            exec.execute(
                HaloAction(label: "x", kind: .appleScript, payload: "say \"hi\""),
                forBundleID: "x"
            ),
            .failed
        )
    }
}

final class KeyboardShortcutTests: XCTestCase {
    func test_parse_acceptsEnglishModifiers() throws {
        let parsed = try XCTUnwrap(KeyboardShortcut.parse("cmd+shift+n"))
        XCTAssertEqual(parsed.keyCode, 45)
        XCTAssertEqual(parsed.modifierMask, 0x100000 | 0x020000)
    }

    func test_parse_acceptsSymbols() throws {
        let parsed = try XCTUnwrap(KeyboardShortcut.parse("⌃⌥F"))
        XCTAssertEqual(parsed.keyCode, 3)
        XCTAssertEqual(parsed.modifierMask, 0x040000 | 0x080000)
    }

    func test_parse_acceptsNamedKeys() throws {
        let parsed = try XCTUnwrap(KeyboardShortcut.parse("cmd+space"))
        XCTAssertEqual(parsed.keyCode, 49)
        let f5 = try XCTUnwrap(KeyboardShortcut.parse("F5"))
        XCTAssertEqual(f5.keyCode, 96)
    }

    func test_parse_rejectsTwoNonModifierTokens() {
        XCTAssertNil(KeyboardShortcut.parse("cmd+a+b"))
    }

    func test_parse_rejectsEmpty() {
        XCTAssertNil(KeyboardShortcut.parse(""))
        XCTAssertNil(KeyboardShortcut.parse("   "))
    }

    func test_displaySymbols_writeBackIsLegible() {
        let parsed = KeyboardShortcut.parse("ctrl+shift+f12")!
        XCTAssertEqual(parsed.displaySymbols, "⌃⇧F12")
    }
}
