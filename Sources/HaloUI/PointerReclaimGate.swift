import Foundation
import CoreGraphics

/// Tells the cursor poll when the pointer should take the highlight back from
/// the scroll wheel or arrow keys. While those inputs own the selection the
/// cursor is normally parked, so the baseline is the first position sampled
/// after the latest wheel or arrow step and movement is cumulative against it:
/// a slow deliberate drag counts, sub-threshold jitter does not. Every step
/// starts a new baseline, so jitter between steps cannot add up to a takeover,
/// and a step taken right after the pointer reclaimed never measures from the
/// previous takeover's origin.
struct PointerReclaimGate {
    /// Points the cursor must travel from the baseline before it counts.
    static let reclaimDistance: CGFloat = 4

    private var baseline: CGPoint?
    private var baselineGeneration: UInt = 0

    /// - Parameter generation: `HaloState.inputSelectionGeneration`, which
    ///   changes on every wheel or arrow step.
    /// - Returns: `true` when the pointer should drive the highlight: either
    ///   nothing needs protecting, or the cursor has moved far enough.
    mutating func pointerMoved(to mouse: CGPoint, inputOwnsSelection: Bool, generation: UInt) -> Bool {
        guard inputOwnsSelection else {
            baseline = nil
            return true
        }
        let origin: CGPoint
        if let baseline, baselineGeneration == generation {
            origin = baseline
        } else {
            origin = mouse
            baseline = mouse
            baselineGeneration = generation
        }
        return hypot(mouse.x - origin.x, mouse.y - origin.y) >= Self.reclaimDistance
    }
}
