import Foundation

public enum FrequencyProfile: String, Sendable, Codable, CaseIterable {
    case mfuOnly
    case balanced
    case mruOnly
}

public struct HaloEngine: Sendable {
    public let profile: FrequencyProfile
    public let pinned: [AppRef]

    public init(profile: FrequencyProfile = .balanced, pinned: [AppRef] = []) {
        self.profile = profile
        self.pinned = pinned
    }

    public func top(n: Int, from records: [UsageRecord], now: Date = Date()) -> [AppRef] {
        precondition((4...12).contains(n), "N must be in 4...12")

        var result: [AppRef] = []
        // Dedupe by bundleID, not by AppRef. Two activations of the same
        // app under different localized names (system language change, app
        // rename, or transient `localizedName` from the OS) used to hash
        // as different `AppRef` values and slipped through the previous
        // `Set<AppRef>` filter, surfacing duplicate slots in the HUD.
        var seenIDs: Set<String> = []

        // 1. Pinned occupy first slots, in pin order, deduped by bundleID.
        for app in pinned where !seenIDs.contains(app.bundleID) {
            if result.count == n { break }
            result.append(app)
            seenIDs.insert(app.bundleID)
        }
        if result.count == n { return result }

        // Roll duplicate-bundle-id records up into a single canonical
        // entry: activations sum, lastUsed takes the most recent. The
        // canonical AppRef is the one with the most recent activation —
        // that's the freshest name string from the OS.
        let canonicalRecords = canonicalise(records)

        // 2. Split remaining slots per profile.
        let remaining = n - result.count
        let (mfuQuota, mruQuota) = quotas(for: remaining)

        let mfuSorted = canonicalRecords
            .sorted { lhs, rhs in
                if lhs.activations != rhs.activations { return lhs.activations > rhs.activations }
                return lhs.lastUsed > rhs.lastUsed
            }
            .map(\.app)

        let mruSorted = canonicalRecords
            .sorted { lhs, rhs in
                if lhs.lastUsed != rhs.lastUsed { return lhs.lastUsed > rhs.lastUsed }
                return lhs.activations > rhs.activations
            }
            .map(\.app)

        var mfuPicked = 0
        for app in mfuSorted where mfuPicked < mfuQuota {
            if seenIDs.insert(app.bundleID).inserted {
                result.append(app)
                mfuPicked += 1
            }
        }

        var mruPicked = 0
        for app in mruSorted where mruPicked < mruQuota {
            if seenIDs.insert(app.bundleID).inserted {
                result.append(app)
                mruPicked += 1
            }
        }

        // 3. Backfill with any leftover MFU order if quotas leave gaps (small N edge cases).
        for app in mfuSorted where result.count < n {
            if seenIDs.insert(app.bundleID).inserted {
                result.append(app)
            }
        }

        return result
    }

    /// Collapse `UsageRecord`s that share a bundleID into one. Activations
    /// sum across the duplicates; `lastUsed` keeps the most recent; the
    /// canonical `AppRef` is the one belonging to the freshest record so
    /// the user-facing display name is the latest one the OS reported.
    private func canonicalise(_ records: [UsageRecord]) -> [UsageRecord] {
        var byID: [String: UsageRecord] = [:]
        for record in records {
            let id = record.app.bundleID
            if let existing = byID[id] {
                let merged = UsageRecord(
                    app: record.lastUsed >= existing.lastUsed ? record.app : existing.app,
                    activations: existing.activations + record.activations,
                    lastUsed: max(existing.lastUsed, record.lastUsed)
                )
                byID[id] = merged
            } else {
                byID[id] = record
            }
        }
        return Array(byID.values)
    }

    private func quotas(for remaining: Int) -> (mfu: Int, mru: Int) {
        switch profile {
        case .mfuOnly:
            return (remaining, 0)
        case .mruOnly:
            return (0, remaining)
        case .balanced:
            let mfu = Int((Double(remaining) * 0.6).rounded(.up))
            let mru = remaining - mfu
            return (mfu, mru)
        }
    }
}
