import XCTest
@testable import HaloCore

final class ActionExecutorTests: XCTestCase {
    final class FakeRuntime: ActionRuntime, @unchecked Sendable {
        var openedFile: URL?
        var openedURL: URL?
        var shouldSucceed = true
        func openFile(at url: URL) -> Bool {
            openedFile = url
            return shouldSucceed
        }
        func openURL(_ url: URL) -> Bool {
            openedURL = url
            return shouldSucceed
        }
    }

    func test_openFolder_expandsTilde_andCallsOpenFile() {
        let fake = FakeRuntime()
        let exec = ActionExecutor(runtime: fake)
        let result = exec.execute(HaloAction(label: "x", kind: .openFolder, payload: "~/Downloads"))
        XCTAssertEqual(result, .executed)
        let expected = (NSString(string: "~/Downloads").expandingTildeInPath) as String
        XCTAssertEqual(fake.openedFile?.path, expected)
        XCTAssertNil(fake.openedURL)
    }

    func test_openFolder_failureBubblesUp() {
        let fake = FakeRuntime()
        fake.shouldSucceed = false
        let exec = ActionExecutor(runtime: fake)
        XCTAssertEqual(
            exec.execute(HaloAction(label: "x", kind: .openFolder, payload: "/no/such/dir")),
            .failed
        )
    }

    func test_openURL_parsesString_andRoutesToOpenURL() {
        let fake = FakeRuntime()
        let exec = ActionExecutor(runtime: fake)
        let result = exec.execute(HaloAction(label: "x", kind: .openURL, payload: "https://example.com/page"))
        XCTAssertEqual(result, .executed)
        XCTAssertEqual(fake.openedURL?.absoluteString, "https://example.com/page")
    }

    func test_openURL_returnsFailedOnUnparseable() {
        let fake = FakeRuntime()
        let exec = ActionExecutor(runtime: fake)
        // Note: most strings parse as URLs; force-fail via empty string.
        let result = exec.execute(HaloAction(label: "x", kind: .openURL, payload: ""))
        XCTAssertEqual(result, .failed)
        XCTAssertNil(fake.openedURL)
    }

    func test_runShortcut_buildsShortcutsURL_withPercentEncodedName() throws {
        let fake = FakeRuntime()
        let exec = ActionExecutor(runtime: fake)
        let result = exec.execute(HaloAction(label: "x", kind: .runShortcut, payload: "Daily Build & Ship"))
        XCTAssertEqual(result, .executed)
        // URLComponents encodes the query value safely. We pull it back out
        // through URLComponents so the assertion is robust to harmless
        // encoding choices ("+" vs "%20" for spaces, etc.).
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
        let result = exec.execute(HaloAction(label: "x", kind: .runShortcut, payload: "   "))
        XCTAssertEqual(result, .failed)
        XCTAssertNil(fake.openedURL)
    }
}
