import XCTest
import Foundation
@testable import HaloUI

@MainActor
final class GridStateTests: XCTestCase {
    private func app(_ id: String, _ name: String) -> GridState.GridApp {
        GridState.GridApp(bundleID: id, name: name, url: URL(fileURLWithPath: "/Applications/\(name).app"))
    }

    func test_filteredApps_matchesNameAndBundleID_caseInsensitively() {
        let state = GridState()
        state.apps = [app("com.example.Editor", "Notes"), app("com.example.mail", "Mail")]

        state.searchQuery = "  EDIT  "
        XCTAssertEqual(state.filteredApps.map(\.bundleID), ["com.example.Editor"])

        state.searchQuery = "MAIL"
        XCTAssertEqual(state.filteredApps.map(\.bundleID), ["com.example.mail"])
    }

    func test_filteredApps_invalidatesWhenAppsAreReplacedOrMoved() {
        let state = GridState()
        state.apps = [app("com.example.a", "Alpha"), app("com.example.b", "Beta")]
        state.searchQuery = "example"
        XCTAssertEqual(state.filteredApps.map(\.bundleID), ["com.example.a", "com.example.b"])

        state.moveApp(bundleID: "com.example.b", near: "com.example.a")
        XCTAssertEqual(state.filteredApps.map(\.bundleID), ["com.example.b", "com.example.a"])

        state.apps = [app("com.example.c", "Gamma")]
        XCTAssertEqual(state.filteredApps.map(\.bundleID), ["com.example.c"])
    }

    func test_searchInput_seedsFirstMatchForReturnCommit() {
        let state = GridState()
        state.apps = [app("com.example.alpha", "Alpha"), app("com.example.beta", "Beta")]

        state.appendSearch("b")

        XCTAssertEqual(state.selectedBundleID, "com.example.beta")
    }
}
