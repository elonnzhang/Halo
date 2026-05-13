import Foundation

/// Records app activations and answers "who was active in the last 7 days".
///
/// Storage: a single JSON blob under `UsageStore.storageKey`. Each app accumulates
/// activation timestamps; counts older than 7 days are dropped at read time.
public final class UsageStore: @unchecked Sendable {
    public static let storageKey = "halo.usage.v1"
    public static let windowSeconds: TimeInterval = 7 * 86_400

    private let defaults: UserDefaults
    private let clock: () -> Date
    private let queue = DispatchQueue(label: "halo.usage-store", qos: .utility)

    public init(defaults: UserDefaults = .standard, clock: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.clock = clock
    }

    public func recordActivation(of app: AppRef) {
        queue.sync {
            var blob = loadBlob()
            blob.timestamps[app, default: []].append(clock())
            blob.names[app.bundleID] = app.name
            saveBlob(blob)
        }
    }

    public func allRecords() -> [UsageRecord] {
        queue.sync {
            let blob = loadBlob()
            let now = clock()
            let cutoff = now.addingTimeInterval(-Self.windowSeconds)

            return blob.timestamps.compactMap { app, stamps in
                let recent = stamps.filter { $0 >= cutoff }
                guard !recent.isEmpty else { return nil }
                return UsageRecord(
                    app: app,
                    activations: recent.count,
                    lastUsed: recent.max() ?? now
                )
            }
        }
    }

    public func reset() {
        queue.sync { defaults.removeObject(forKey: Self.storageKey) }
    }

    // MARK: - Storage

    private struct Blob: Codable {
        var timestamps: [AppRef: [Date]] = [:]
        var names: [String: String] = [:]

        // AppRef as a JSON dictionary key needs a string projection.
        private enum CodingKeys: String, CodingKey { case entries, names }

        private struct Entry: Codable {
            let app: AppRef
            let stamps: [Date]
        }

        init() {}

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let entries = (try? c.decode([Entry].self, forKey: .entries)) ?? []
            self.timestamps = Dictionary(uniqueKeysWithValues: entries.map { ($0.app, $0.stamps) })
            self.names = (try? c.decode([String: String].self, forKey: .names)) ?? [:]
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            let entries = timestamps.map { Entry(app: $0.key, stamps: $0.value) }
            try c.encode(entries, forKey: .entries)
            try c.encode(names, forKey: .names)
        }
    }

    private func loadBlob() -> Blob {
        guard let data = defaults.data(forKey: Self.storageKey),
              let blob = try? JSONDecoder().decode(Blob.self, from: data)
        else { return Blob() }
        return blob
    }

    private func saveBlob(_ blob: Blob) {
        guard let data = try? JSONEncoder().encode(blob) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}
