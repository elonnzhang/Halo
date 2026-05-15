import Foundation

/// One named profile's worth of bindings. v1.2 scope: pinned slots,
/// overflow pins, identity-colour overrides. Everything else
/// (`slotCount`, `frequencyProfile`, `whitelist.v1`, hotkey, layout,
/// language, sound, …) stays user-global on `AppPreferences`.
public struct BindingProfile: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var pinnedBundleIDs: [String?]
    public var overflowPinnedBundleIDs: [String]
    public var identityOverrides: [String: IdentityColor]

    public init(
        id: UUID = UUID(),
        name: String,
        pinnedBundleIDs: [String?] = Array(repeating: nil, count: 8),
        overflowPinnedBundleIDs: [String] = [],
        identityOverrides: [String: IdentityColor] = [:]
    ) {
        self.id = id
        self.name = name
        self.pinnedBundleIDs = pinnedBundleIDs
        self.overflowPinnedBundleIDs = overflowPinnedBundleIDs
        self.identityOverrides = identityOverrides
    }
}

extension BindingProfile {
    /// Canonical empty profile used at first launch and during migration
    /// when no legacy keys exist. Pin-array length defaults to 8 to match
    /// `AppPreferences.registerDefaults`; the projection layer adjusts it
    /// to whatever the user's global `slotCount` is on first read.
    public static func freshDefault() -> BindingProfile {
        BindingProfile(name: "Default")
    }

    /// Return a new profile with its pin array resized to `newN`. Same
    /// shrink/grow semantics the old `AppPreferences.resizePinned(from:to:)`
    /// used: shrinking spills trailing non-nil pins into overflow; growing
    /// refills leading nil slots from overflow in order.
    public func resizing(slotCount newN: Int) -> BindingProfile {
        let clamped = max(4, min(12, newN))
        guard clamped != pinnedBundleIDs.count else { return self }

        var pins = pinnedBundleIDs
        var overflow = overflowPinnedBundleIDs

        if clamped < pins.count {
            let spilled = pins[clamped...].compactMap { $0 }
            overflow.append(contentsOf: spilled)
            pins = Array(pins.prefix(clamped))
        } else {
            pins.append(contentsOf: Array(repeating: nil, count: clamped - pins.count))
            var remaining: [String] = []
            for id in overflow {
                if let firstEmpty = pins.firstIndex(where: { $0 == nil }) {
                    pins[firstEmpty] = id
                } else {
                    remaining.append(id)
                }
            }
            overflow = remaining
        }

        var copy = self
        copy.pinnedBundleIDs = pins
        copy.overflowPinnedBundleIDs = overflow
        return copy
    }
}
