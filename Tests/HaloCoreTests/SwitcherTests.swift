import XCTest
@testable import HaloCore

final class SwitcherTests: XCTestCase {
    func test_switchTo_activatesRunningApp_whenPresent() {
        let runtime = StubRuntime()
        runtime.running = ["com.apple.Safari"]
        let switcher = Switcher(runtime: runtime)

        let outcome = switcher.switchTo(bundleID: "com.apple.Safari")

        XCTAssertEqual(outcome, .activated)
        XCTAssertEqual(runtime.activated, ["com.apple.Safari"])
        XCTAssertEqual(runtime.launched, [])
    }

    func test_switchTo_launchesApp_whenNotRunning() {
        let runtime = StubRuntime()
        runtime.running = []
        let switcher = Switcher(runtime: runtime)

        let outcome = switcher.switchTo(bundleID: "com.apple.Notes")

        XCTAssertEqual(outcome, .launched)
        XCTAssertEqual(runtime.activated, [])
        XCTAssertEqual(runtime.launched, ["com.apple.Notes"])
    }

    func test_switchTo_returnsFailed_whenLaunchUnavailable() {
        let runtime = StubRuntime()
        runtime.running = []
        runtime.launchSucceedsFor = []
        let switcher = Switcher(runtime: runtime)

        let outcome = switcher.switchTo(bundleID: "com.nonexistent.app")

        XCTAssertEqual(outcome, .failed)
    }
}

private final class StubRuntime: AppRuntime, @unchecked Sendable {
    var running: [String] = []
    var activated: [String] = []
    var launched: [String] = []
    /// When nil, all bundle IDs launch successfully. When set, only IDs in the set launch.
    var launchSucceedsFor: Set<String>? = nil

    func isRunning(bundleID: String) -> Bool { running.contains(bundleID) }

    func activate(bundleID: String) -> Bool {
        activated.append(bundleID)
        return true
    }

    func launch(bundleID: String) -> Bool {
        if let allowed = launchSucceedsFor, !allowed.contains(bundleID) { return false }
        launched.append(bundleID)
        return true
    }
}
