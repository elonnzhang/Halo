import XCTest
@testable import HaloCore

final class HaloEngineTests: XCTestCase {
    private let safari = AppRef(bundleID: "com.apple.Safari", name: "Safari")
    private let slack = AppRef(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")
    private let mail = AppRef(bundleID: "com.apple.mail", name: "Mail")
    private let notes = AppRef(bundleID: "com.apple.Notes", name: "Notes")

    func test_top4_ordersByActivationCount_balanced() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let records: [UsageRecord] = [
            UsageRecord(app: safari, activations: 50, lastUsed: now.addingTimeInterval(-3600)),
            UsageRecord(app: slack,  activations: 30, lastUsed: now.addingTimeInterval(-7200)),
            UsageRecord(app: mail,   activations: 20, lastUsed: now.addingTimeInterval(-10_800)),
            UsageRecord(app: notes,  activations: 5,  lastUsed: now.addingTimeInterval(-14_400)),
        ]
        let engine = HaloEngine(profile: .balanced)

        let result = engine.top(n: 4, from: records, now: now)

        XCTAssertEqual(result, [safari, slack, mail, notes])
    }

    func test_pinnedAppsOccupyLeadingSlots_overridingActivationOrder() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let records: [UsageRecord] = [
            UsageRecord(app: safari, activations: 50, lastUsed: now.addingTimeInterval(-3600)),
            UsageRecord(app: slack,  activations: 30, lastUsed: now.addingTimeInterval(-7200)),
            UsageRecord(app: mail,   activations: 20, lastUsed: now.addingTimeInterval(-10_800)),
            UsageRecord(app: notes,  activations: 5,  lastUsed: now.addingTimeInterval(-14_400)),
        ]
        let engine = HaloEngine(profile: .balanced, pinned: [notes, mail])

        let result = engine.top(n: 4, from: records, now: now)

        XCTAssertEqual(result.prefix(2), [notes, mail].prefix(2),
                       "pinned apps should occupy the leading slots in pin order")
        XCTAssertEqual(Set(result), Set([notes, mail, safari, slack]),
                       "remaining slots should pull from MFU/MRU without duplicating pins")
    }

    func test_mfuOnly_profileIgnoresRecency() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        // notes is the most recent but the least activated; mfuOnly must rank by count.
        let records: [UsageRecord] = [
            UsageRecord(app: safari, activations: 50, lastUsed: now.addingTimeInterval(-86_400)),
            UsageRecord(app: slack,  activations: 30, lastUsed: now.addingTimeInterval(-43_200)),
            UsageRecord(app: mail,   activations: 20, lastUsed: now.addingTimeInterval(-7200)),
            UsageRecord(app: notes,  activations: 5,  lastUsed: now.addingTimeInterval(-60)),
        ]
        let engine = HaloEngine(profile: .mfuOnly)

        let result = engine.top(n: 4, from: records, now: now)

        XCTAssertEqual(result, [safari, slack, mail, notes])
    }

    func test_mruOnly_profileIgnoresActivationCount() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let records: [UsageRecord] = [
            UsageRecord(app: safari, activations: 50, lastUsed: now.addingTimeInterval(-86_400)),
            UsageRecord(app: slack,  activations: 30, lastUsed: now.addingTimeInterval(-43_200)),
            UsageRecord(app: mail,   activations: 20, lastUsed: now.addingTimeInterval(-7200)),
            UsageRecord(app: notes,  activations: 5,  lastUsed: now.addingTimeInterval(-60)),
        ]
        let engine = HaloEngine(profile: .mruOnly)

        let result = engine.top(n: 4, from: records, now: now)

        XCTAssertEqual(result, [notes, mail, slack, safari])
    }

    func test_top8_balancedSplitsSixMFU_andTwoMRU() {
        // n=8, balanced: ceil(8*0.6)=5 MFU + 3 MRU? No — handoff formula is over the
        // post-pin remaining count; with no pins, remaining=8, so MFU=ceil(8*0.6)=5, MRU=3.
        let now = Date(timeIntervalSince1970: 1_000_000)
        let apps = (0..<10).map { i in AppRef(bundleID: "app.\(i)", name: "App\(i)") }
        // Activations descend; recency ascends (older index = more recent).
        let records: [UsageRecord] = apps.enumerated().map { idx, app in
            UsageRecord(
                app: app,
                activations: 100 - idx * 5,
                lastUsed: now.addingTimeInterval(TimeInterval(-3600 * (10 - idx)))
            )
        }
        let engine = HaloEngine(profile: .balanced)

        let result = engine.top(n: 8, from: records, now: now)

        XCTAssertEqual(result.count, 8)
        // MFU portion = top 5 by activation = apps[0..<5]
        XCTAssertEqual(Array(result.prefix(5)), Array(apps.prefix(5)))
        // MRU portion fills the rest from the most-recent end (app 9, 8, 7).
        XCTAssertEqual(Set(result.suffix(3)), Set([apps[9], apps[8], apps[7]]))
    }

    func test_emptyRecords_returnsEmptyWhenNoPins() {
        let engine = HaloEngine(profile: .balanced)
        XCTAssertEqual(engine.top(n: 4, from: []), [])
    }
}
