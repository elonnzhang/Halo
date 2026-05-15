import Foundation

/// One named profile's worth of bindings. v1.2 scope: pinned slots,
/// overflow pins, identity-colour overrides. v1.3 (handoff alignment):
/// `slotCount` and `tint` moved per-profile so each scene can have its own
/// wheel size and ambient identity colour. Everything else
/// (`frequencyProfile`, `whitelist.v1`, hotkey, layout, language, sound, …)
/// stays user-global on `AppPreferences`.
public struct BindingProfile: Codable, Identifiable, Sendable, Equatable {
    public let id: UUID
    public var name: String
    public var pinnedBundleIDs: [String?]
    public var overflowPinnedBundleIDs: [String]
    public var identityOverrides: [String: IdentityColor]
    /// How many slots this profile shows. Clamped to 4...12 on read/write
    /// just like the legacy global value. v1.2 plists lack this key —
    /// `Codable` falls through to the default decoder, so the
    /// `nilDecodingFallback` in `init(from:)` synthesises it from the
    /// pin-array length below.
    public var slotCount: Int
    /// Ambient profile tint applied to the wheel's halo glow when no slot
    /// is hovered. `nil` keeps Halo's idle look untinted (current
    /// behaviour). Picker UI ships in v1.3.
    public var tint: IdentityColor?

    public init(
        id: UUID = UUID(),
        name: String,
        pinnedBundleIDs: [String?] = Array(repeating: nil, count: 8),
        overflowPinnedBundleIDs: [String] = [],
        identityOverrides: [String: IdentityColor] = [:],
        slotCount: Int = 8,
        tint: IdentityColor? = nil
    ) {
        self.id = id
        self.name = name
        self.pinnedBundleIDs = pinnedBundleIDs
        self.overflowPinnedBundleIDs = overflowPinnedBundleIDs
        self.identityOverrides = identityOverrides
        self.slotCount = max(4, min(12, slotCount))
        self.tint = tint
    }

    /// Custom decoder so v1.2 plists (which lack `slotCount` and `tint`)
    /// still load. Missing `slotCount` inherits the pin-array length so
    /// the profile keeps rendering at whatever width it was last sized
    /// to; missing `tint` stays `nil` (no ambient glow).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let id = try c.decode(UUID.self, forKey: .id)
        let name = try c.decode(String.self, forKey: .name)
        let pins = try c.decode([String?].self, forKey: .pinnedBundleIDs)
        let overflow = try c.decode([String].self, forKey: .overflowPinnedBundleIDs)
        let overrides = try c.decode([String: IdentityColor].self, forKey: .identityOverrides)
        let inferredSlotCount = max(4, min(12, pins.count))
        let slotCount = (try c.decodeIfPresent(Int.self, forKey: .slotCount)) ?? inferredSlotCount
        let tint = try c.decodeIfPresent(IdentityColor.self, forKey: .tint)
        self.init(
            id: id,
            name: name,
            pinnedBundleIDs: pins,
            overflowPinnedBundleIDs: overflow,
            identityOverrides: overrides,
            slotCount: slotCount,
            tint: tint
        )
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
        var copy = self
        copy.slotCount = clamped
        guard clamped != pinnedBundleIDs.count else { return copy }

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

        copy.pinnedBundleIDs = pins
        copy.overflowPinnedBundleIDs = overflow
        return copy
    }
}
