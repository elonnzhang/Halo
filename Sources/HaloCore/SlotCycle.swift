import Foundation

/// Pure helpers for slot-cycling logic. Lives in HaloCore so XCTest can
/// hit it without dragging in SwiftUI / AppKit. Consumed by
/// `HaloState.advanceSelection` and any future caller that needs to
/// resolve "given this delta, this current hover, this scroll anchor —
/// which slot should be highlighted next?".
public enum SlotCycle {
    /// Anchor priority: cursor hover wins; otherwise the scroll anchor
    /// (e.g. from the highlight-frontmost-on-summon feature) if it's
    /// inside the visible slot count; otherwise slot 0. The anchor is
    /// returned alongside the chosen index so the caller can decide
    /// whether to consume it (one-shot) or keep it.
    public static func nextIndex(
        delta: Int,
        slotCount: Int,
        currentHover: Int?,
        scrollAnchor: Int?
    ) -> Int {
        guard slotCount > 0 else { return 0 }
        let anchor: Int
        if let hover = currentHover {
            anchor = hover
        } else if let scroll = scrollAnchor, scroll < slotCount {
            anchor = scroll
        } else {
            anchor = 0
        }
        return ((anchor + delta) % slotCount + slotCount) % slotCount
    }

    /// True when `nextIndex` consumed the scroll anchor — i.e. there was
    /// no cursor hover but a usable scroll anchor was present. Callers
    /// clear the anchor after the first scroll within a summon.
    public static func consumedScrollAnchor(
        currentHover: Int?,
        scrollAnchor: Int?,
        slotCount: Int
    ) -> Bool {
        guard currentHover == nil else { return false }
        return scrollAnchor.map { $0 < slotCount } ?? false
    }
}
