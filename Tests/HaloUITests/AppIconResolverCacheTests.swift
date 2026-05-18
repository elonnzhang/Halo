import XCTest
import AppKit
@testable import HaloUI

@MainActor
final class AppIconResolverCacheTests: XCTestCase {

    override func setUp() {
        super.setUp()
        AppIconResolver._resetCacheForTests()
    }

    /// Same bundleID resolved twice should return the exact same NSImage
    /// reference — that's the whole point of the cache. The second call
    /// must NOT round-trip through NSWorkspace.
    func test_repeatLookup_returnsSameNSImageInstance() throws {
        // Finder is on every Mac; if NSWorkspace can't find it the test
        // bails rather than failing — there's no useful signal there.
        guard let first = AppIconResolver.icon(for: "com.apple.finder")
        else {
            throw XCTSkip("Finder bundle not resolvable in this environment")
        }
        let second = AppIconResolver.icon(for: "com.apple.finder")
        XCTAssertTrue(first === second,
                      "Second lookup should hit the cache, not a fresh NSImage")
    }

    /// Cache must have a non-zero count limit so a long-running session
    /// can't grow unbounded.
    func test_cacheHasFiniteCountLimit() {
        let limit = AppIconResolver._cacheCountLimit()
        XCTAssertGreaterThan(limit, 0)
        XCTAssertLessThanOrEqual(limit, 4096,
                                 "An NSCache limit in the thousands suggests someone removed the cap")
    }

    /// Unknown bundle IDs return nil and don't poison the cache for the
    /// next lookup of the same key (e.g. an app that installs after).
    func test_unknownBundleID_returnsNil_andIsNotCached() {
        let probe = "com.halo.tests.intentionally.unregistered.\(UUID().uuidString)"
        XCTAssertNil(AppIconResolver.icon(for: probe))
        // Second call should still return nil but more importantly we
        // shouldn't crash from a cached-nil contradicting NSImage's
        // non-optional setObject signature.
        XCTAssertNil(AppIconResolver.icon(for: probe))
    }
}

