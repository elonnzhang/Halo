import XCTest
@testable import HaloCore

final class UsageStoreTests: XCTestCase {
    private let safari = AppRef(bundleID: "com.apple.Safari", name: "Safari")
    private let slack = AppRef(bundleID: "com.tinyspeck.slackmacgap", name: "Slack")

    private func makeStore(now: Date) -> UsageStore {
        let suite = "halo.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return UsageStore(defaults: defaults, clock: { now })
    }

    func test_recordActivation_incrementsCountAndUpdatesLastUsed() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let store = makeStore(now: now)

        store.recordActivation(of: safari)
        store.recordActivation(of: safari)
        store.recordActivation(of: slack)

        let records = store.allRecords()
        let safariRec = records.first { $0.app == safari }
        let slackRec = records.first { $0.app == slack }
        XCTAssertEqual(safariRec?.activations, 2)
        XCTAssertEqual(slackRec?.activations, 1)
        XCTAssertEqual(safariRec?.lastUsed, now)
    }

    func test_activationsOlderThan7Days_areDroppedFromCount() {
        var current = Date(timeIntervalSince1970: 1_000_000)
        var defaults: UserDefaults
        let suite = "halo.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let store = UsageStore(defaults: defaults, clock: { current })

        store.recordActivation(of: safari)         // day 0
        current = current.addingTimeInterval(86_400 * 8)  // jump 8 days forward
        store.recordActivation(of: safari)         // day 8

        let records = store.allRecords()
        let safariRec = records.first { $0.app == safari }
        XCTAssertEqual(safariRec?.activations, 1,
                       "day-0 activation should fall outside the 7-day window")
    }

    func test_persistence_roundTripsAcrossInstances() {
        let now = Date(timeIntervalSince1970: 1_000_000)
        let suite = "halo.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)

        let storeA = UsageStore(defaults: defaults, clock: { now })
        storeA.recordActivation(of: safari)
        storeA.recordActivation(of: safari)

        let storeB = UsageStore(defaults: defaults, clock: { now })
        let rec = storeB.allRecords().first { $0.app == safari }
        XCTAssertEqual(rec?.activations, 2)
    }
}
