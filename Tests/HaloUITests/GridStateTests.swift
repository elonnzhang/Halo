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

    func test_searchAcceptsSpaces_soMultiWordNamesStayFindable() {
        let state = GridState()
        state.apps = [app("com.example.studio", "Visual Studio"), app("com.example.visual", "Visualizer")]

        "visual s".forEach { state.appendSearch($0) }

        XCTAssertEqual(state.filteredApps.map(\.bundleID), ["com.example.studio"])
        XCTAssertEqual(state.selectedBundleID, "com.example.studio")
    }

    func test_endVisit_abortsTheLaunchButKeepsWhatIsOnScreen() {
        let state = GridState()
        let ids = ["com.example.a", "com.example.b", "com.example.c"]
        state.apps = ids.map { app($0, $0) }
        state.lens.sync(ids: ids, metrics: .scaled(1))
        state.searchQuery = "example"
        state.selectedBundleID = "com.example.b"
        state.committingBundleID = "com.example.b"
        state.draggingBundleID = "com.example.c"

        state.endVisit()

        XCTAssertNil(state.committingBundleID, "a launch waiting on its press burst must not fire")
        XCTAssertNil(state.draggingBundleID)
        XCTAssertFalse(state.lens.isMoving)
        // The panel fades out showing the same icons, search and selection.
        XCTAssertEqual(state.lens.cells.count, ids.count)
        XCTAssertEqual(state.searchQuery, "example")
        XCTAssertEqual(state.selectedBundleID, "com.example.b")
    }

    func test_pointerSelectionPause_coversEveryMotionSource() {
        let state = GridState()
        XCTAssertFalse(state.isPointerSelectionPaused)

        state.pointerSelectionSuppressed = true
        XCTAssertTrue(state.isPointerSelectionPaused)
        state.pointerSelectionSuppressed = false

        state.draggingBundleID = "com.example.a"
        XCTAssertTrue(state.isPointerSelectionPaused)
        state.draggingBundleID = nil

        let ids = ["com.example.a", "com.example.b"]
        state.lens.sync(ids: ids, metrics: .scaled(1))
        state.lens.scroll(by: CGSize(width: 10, height: 0))
        XCTAssertTrue(state.isPointerSelectionPaused, "a pending lens settle pauses the pointer")
        state.lens.stop()
        XCTAssertFalse(state.isPointerSelectionPaused)
    }
}
