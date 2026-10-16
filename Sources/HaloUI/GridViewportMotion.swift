import AppKit
import Foundation

/// Per-grid transient motion, driven only while a coast or zoom is active.
/// GridState always contains presentation values, so rendering and pointer
/// hit-testing see the same viewport, including between wheel notches.
@MainActor
final class GridViewportMotion {
    private weak var state: GridState?
    private var ticker: Task<Void, Never>?
    private var coast: HoneycombViewportGeometry.Coast?
    private var zoomSpring: HoneycombViewportGeometry.ZoomSpring?
    private var startedAt: TimeInterval = 0

    init(state: GridState) { self.state = state }

    func stop() {
        ticker?.cancel()
        ticker = nil
        coast = nil
        zoomSpring = nil
        state?.isViewportMoving = false
    }

    func beginGesture() {
        stop()
        state?.isViewportMoving = true
    }

    func coast(by travel: CGSize, reduceMotion: Bool) {
        stop()
        guard let state, !reduceMotion, hypot(travel.width, travel.height) > 2 else { return }
        coast = HoneycombViewportGeometry.Coast(origin: state.panOffset, predictedTravel: travel)
        start()
    }

    func zoom(by delta: CGFloat, reduceMotion: Bool) {
        guard let state else { return }
        let now = ProcessInfo.processInfo.systemUptime
        let previous = zoomSpring?.sample(at: now - startedAt)
        let target = max(0.5, min(2.5, (zoomSpring?.target ?? state.zoomLevel) + delta))
        if reduceMotion {
            stop()
            if state.zoomLevel != target { state.zoomLevel = target }
            return
        }
        // Sample the old spring before cancellation. The next spring begins
        // at this presentation value and velocity, even after a frame stall.
        stop()
        if let previous { state.zoomLevel = max(0.5, min(2.5, previous.value)) }
        guard abs(target - state.zoomLevel) > 0.0001 || abs(previous?.velocity ?? 0) > 0.005 else { return }
        zoomSpring = HoneycombViewportGeometry.ZoomSpring(
            origin: state.zoomLevel, target: target, velocity: previous?.velocity ?? 0)
        start()
    }

    private func start() {
        startedAt = ProcessInfo.processInfo.systemUptime
        state?.isViewportMoving = true
        let fps = min(120, max(60, NSScreen.main?.maximumFramesPerSecond ?? 60))
        let interval = UInt64(1_000_000_000 / fps)
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard self?.advance(at: ProcessInfo.processInfo.systemUptime) == true else { return }
                do { try await Task.sleep(nanoseconds: interval) }
                catch { return }
            }
        }
    }

    /// Internal for deterministic lifecycle tests; no sleep is necessary.
    @discardableResult
    func advance(at now: TimeInterval) -> Bool {
        guard let state else { stop(); return false }
        let elapsed = now - startedAt
        if let coast {
            state.panOffset = coast.value(at: elapsed, limits: state.viewportPanLimits)
            if coast.isFinished(at: elapsed, limits: state.viewportPanLimits) {
                self.coast = nil
            }
        }
        if let spring = zoomSpring {
            let sample = spring.sample(at: elapsed)
            state.zoomLevel = max(0.5, min(2.5, sample.value))
            if spring.isFinished(at: elapsed) {
                state.zoomLevel = spring.target
                zoomSpring = nil
            }
        }
        if coast == nil, zoomSpring == nil { stop(); return false }
        return true
    }
}
