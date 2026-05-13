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
        var seen: Set<AppRef> = []

        // 1. Pinned occupy first slots, in pin order, deduped.
        for app in pinned where !seen.contains(app) {
            if result.count == n { break }
            result.append(app)
            seen.insert(app)
        }
        if result.count == n { return result }

        // 2. Split remaining slots per profile.
        let remaining = n - result.count
        let (mfuQuota, mruQuota) = quotas(for: remaining)

        let mfuSorted = records
            .sorted { lhs, rhs in
                if lhs.activations != rhs.activations { return lhs.activations > rhs.activations }
                return lhs.lastUsed > rhs.lastUsed
            }
            .map(\.app)

        let mruSorted = records
            .sorted { lhs, rhs in
                if lhs.lastUsed != rhs.lastUsed { return lhs.lastUsed > rhs.lastUsed }
                return lhs.activations > rhs.activations
            }
            .map(\.app)

        var mfuPicked = 0
        for app in mfuSorted where mfuPicked < mfuQuota {
            if seen.insert(app).inserted {
                result.append(app)
                mfuPicked += 1
            }
        }

        var mruPicked = 0
        for app in mruSorted where mruPicked < mruQuota {
            if seen.insert(app).inserted {
                result.append(app)
                mruPicked += 1
            }
        }

        // 3. Backfill with any leftover MFU order if quotas leave gaps (small N edge cases).
        for app in mfuSorted where result.count < n {
            if seen.insert(app).inserted {
                result.append(app)
            }
        }

        return result
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
