import AppKit

/// Process-lifetime icon cache. `NSWorkspace.shared.icon(forFile:)`
/// returns a fresh `NSImage` per call that lazy-loads bitmaps off the
/// disk the first time it's drawn; ~15 call sites read the same handful
/// of icons across each summon. Caching the `NSImage` reference (it's a
/// class) collapses repeat lookups to a dict hit and reuses the
/// already-decoded bitmap rep, which is the bit that costs real time.
///
/// `NSCache` is thread-safe, evicts under memory pressure, and is
/// capped so a long-running session doesn't trend unbounded.
public enum AppIconResolver {
    /// `NSCache` is documented thread-safe (Apple, NSCache.h), so the
    /// "unchecked" annotation is sound. Swift 6 doesn't know that
    /// because `NSCache` isn't `Sendable`-annotated in the SDK.
    nonisolated(unsafe) private static let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 256
        return c
    }()

    public static func icon(for bundleID: String) -> NSImage? {
        let key = bundleID as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return nil }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        cache.setObject(image, forKey: key)
        return image
    }

    public static func frontmostIcon() -> NSImage? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let id = app.bundleIdentifier
        else { return nil }
        return icon(for: id)
    }

    /// Force-load and cache an icon. Designed for off-main prefetch from
    /// `GridState.loadApps` so the first ALL render finds the icons
    /// already in cache.
    public static func prefetch(bundleID: String) {
        _ = icon(for: bundleID)
    }

    /// Test seam. Cache is private; tests reach for behaviour via the
    /// two helpers below.
    public static func _resetCacheForTests() {
        cache.removeAllObjects()
    }

    public static func _cacheCountLimit() -> Int { cache.countLimit }
}
