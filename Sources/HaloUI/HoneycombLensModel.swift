import AppKit
import Foundation
import SwiftUI

/// Pan state of the ALL lens honeycomb: the honeycomb point drawn in
/// the middle of the view, the glide that eases it to a cell, and pointer /
/// scroll input. Every pan settles with the nearest app centred and
/// selected, so Return opens what sits in the middle.
///
/// Apps occupy honeycomb slots. Slots that would be drawn under the profile
/// strip are reserved, and their apps take the nearest free slot. The
/// reservation is recomputed only when the honeycomb comes to rest, so no
/// app changes slot mid-motion; the reflow then animates.
@MainActor
public final class HoneycombLensModel: ObservableObject {
    @Published public private(set) var at: CGPoint = .zero
    /// Each app's current slot centre, indexed like `ids`.
    @Published public private(set) var cells: [CGPoint] = []
    public private(set) var ids: [String] = []
    /// Spiral slots: one per app plus spares for strip-displaced apps.
    private var slots: [CGPoint] = []
    private var reservation: Reservation?
    private var reservedAt: CGPoint?
    public private(set) var metrics = HoneycombLensGeometry.Metrics.scaled(1)
    private var bounds: CGRect = .zero
    private weak var state: GridState?

    private var glideFrom: CGPoint = .zero
    private var glideTo: CGPoint?
    private var glideStart: TimeInterval = 0
    private var ticker: Task<Void, Never>?
    private var settleTask: Task<Void, Never>?

    private var dragLast: CGPoint?
    private var dragTravel: CGFloat = 0
    private var velocity: CGSize = .zero
    private var lastMove: TimeInterval = 0

    public var isDragging: Bool { dragLast != nil }
    /// True while dragging, gliding or waiting to settle; hover selection
    /// pauses so icons sliding under a still cursor don't steal it.
    public var isMoving: Bool { dragLast != nil || glideTo != nil || settleTask != nil }

    /// The app drawn in the middle of the lens.
    public var centredID: String? {
        HoneycombLensGeometry.nearest(in: cells, to: at).map { ids[$0] }
    }

    /// Where the strip sits, refreshed by the view each layout.
    struct Reservation: Equatable {
        var viewSize: CGSize
        var centre: CGPoint
        var strip: CGRect?
    }

    init(state: GridState) { self.state = state }

    private var now: TimeInterval { ProcessInfo.processInfo.systemUptime }
    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Rebuild cells when the app list or metrics change. A changed count
    /// (search, rescan) jumps straight to the selected app, as onevra does.
    func sync(ids: [String], metrics: HoneycombLensGeometry.Metrics) {
        guard ids != self.ids || metrics != self.metrics else { return }
        let rebuild = ids.count != self.ids.count || metrics.spacing != self.metrics.spacing
            || metrics.stretch != self.metrics.stretch
        self.ids = ids
        self.metrics = metrics
        guard rebuild else {
            // Same count, different apps (search): centre the selection.
            if let id = state?.selectedBundleID { centre(on: id) }
            return
        }
        stop()
        slots = HoneycombLensGeometry.cells(
            count: ids.isEmpty ? 0 : ids.count + HoneycombLensGeometry.spareCells,
            spacing: metrics.spacing, stretch: metrics.stretch)
        cells = Array(slots.prefix(ids.count))
        bounds = HoneycombLensGeometry.bounds(of: cells)
        reservedAt = nil
        guard !ids.isEmpty else { at = .zero; return }
        let index = state?.selectedBundleID.flatMap { ids.firstIndex(of: $0) } ?? 0
        at = cells[index]
        if state?.selectedBundleID != ids[index] { state?.selectedBundleID = ids[index] }
        reflow(animated: false)
    }

    /// The view reports the strip's position; a change re-reserves at rest.
    func reserve(_ reservation: Reservation) {
        guard reservation != self.reservation else { return }
        let first = self.reservation == nil
        self.reservation = reservation
        reservedAt = nil
        if !isMoving { reflow(animated: !first) }
    }

    /// Re-reserve the strip for the current pan. Unblocked apps keep their
    /// slot; the focal app is never under the strip, so it stays centred.
    private func reflow(animated: Bool) {
        guard let r = reservation, !ids.isEmpty, slots.count >= ids.count, reservedAt != at else { return }
        reservedAt = at
        let blocked = HoneycombLensGeometry.blockedSlots(
            slots, at: at, viewSize: r.viewSize, centre: r.centre, metrics: metrics, strip: r.strip)
        let assignment = HoneycombLensGeometry.assign(
            count: ids.count, slots: slots, blocked: blocked, metrics: metrics)
        let next = assignment.map { slots[$0] }
        guard next != cells else { return }
        let middle = HoneycombLensGeometry.nearest(in: cells, to: at)
        let apply = { [self] in
            cells = next
            bounds = HoneycombLensGeometry.bounds(of: next)
            // Keep the focal app centred if the reflow moved it.
            if let middle, cells[middle] != at { at = cells[middle]; reservedAt = at }
        }
        if animated && !reduceMotion {
            withAnimation(.Halo.gridReflow(reduceMotion: false), apply)
        } else {
            apply()
        }
    }

    /// Keyboard or search selection pans the chosen app to the middle.
    public func centre(on bundleID: String) {
        guard !isDragging, let index = ids.firstIndex(of: bundleID), index < cells.count else { return }
        glide(to: cells[index])
    }

    /// Native scroll deltas: content follows the fingers, as in ALL.
    public func scroll(by delta: CGSize) {
        guard !cells.isEmpty else { return }
        cancelGlide()
        let ratio = metrics.panRatio
        at = HoneycombLensGeometry.pan(
            at, by: CGSize(width: -delta.width * ratio, height: -delta.height * ratio), within: bounds)
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(nanoseconds: UInt64(HoneycombLensGeometry.settleDelay * 1e9)) }
            catch { return }
            guard let self, !self.isDragging else { return }
            self.settleTask = nil
            self.settle(toward: self.at)
            if self.glideTo == nil { self.didComeToRest() }
        }
    }

    /// A press catches a moving honeycomb.
    func drag(to location: CGPoint) {
        let time = now
        guard let last = dragLast else {
            cancelGlide()
            settleTask?.cancel()
            settleTask = nil
            dragLast = location
            dragTravel = 0
            velocity = .zero
            lastMove = time
            return
        }
        let dx = location.x - last.x
        let dy = location.y - last.y
        dragLast = location
        dragTravel += hypot(dx, dy)
        let ratio = metrics.panRatio
        at = HoneycombLensGeometry.pan(
            at, by: CGSize(width: -dx * ratio, height: -dy * ratio), within: bounds)
        let dt = CGFloat(time - lastMove)
        if dt > 0 {
            velocity = CGSize(width: 0.7 * (-dx / dt) + 0.3 * velocity.width,
                              height: 0.7 * (-dy / dt) + 0.3 * velocity.height)
        }
        lastMove = time
    }

    /// Returns true for a click, which the view hit-tests. A released drag
    /// continues at its speed and settles on the nearest app.
    @discardableResult
    func endDrag() -> Bool {
        defer { dragLast = nil }
        guard dragLast != nil else { return false }
        if dragTravel < HoneycombLensGeometry.tapSlop {
            if glideTo == nil { didComeToRest() }
            return true
        }
        if now - lastMove > 0.08 { velocity = .zero }
        let inertia = HoneycombLensGeometry.inertia
        settle(toward: CGPoint(x: at.x + velocity.width * inertia, y: at.y + velocity.height * inertia))
        return false
    }

    /// Leaving the grid forgets the pan; the next entry starts centred.
    func reset() {
        stop()
        dragLast = nil
        ids = []
        cells = []
        slots = []
        reservation = nil
        reservedAt = nil
        at = .zero
    }

    func stop() {
        settleTask?.cancel()
        settleTask = nil
        cancelGlide()
    }

    /// Called once a glide ends or a scroll settles.
    private func didComeToRest() {
        settleTask = nil
        reflow(animated: true)
    }

    private func settle(toward point: CGPoint) {
        guard let index = HoneycombLensGeometry.nearest(in: cells, to: point) else { return }
        glide(to: cells[index])
        if state?.selectedBundleID != ids[index] { state?.selectedBundleID = ids[index] }
    }

    private func glide(to target: CGPoint) {
        if glideTo == target { return }
        if glideTo == nil, at == target { didComeToRest(); return }
        if reduceMotion {
            cancelGlide()
            at = target
            didComeToRest()
            return
        }
        glideFrom = at
        glideTo = target
        glideStart = now
        guard ticker == nil else { return }
        let fps = min(120, max(60, NSScreen.main?.maximumFramesPerSecond ?? 60))
        let interval = UInt64(1_000_000_000 / fps)
        ticker = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.advance(at: self.now) else { return }
                do { try await Task.sleep(nanoseconds: interval) }
                catch { return }
            }
        }
    }

    /// Internal for deterministic tests.
    @discardableResult
    func advance(at time: TimeInterval) -> Bool {
        guard let target = glideTo else { ticker = nil; return false }
        let t = CGFloat((time - glideStart) / HoneycombLensGeometry.glideDuration)
        if t >= 1 {
            at = target
            glideTo = nil
            ticker = nil
            didComeToRest()
            return false
        }
        let e = HoneycombLensGeometry.easeInOut(t)
        at = CGPoint(x: glideFrom.x + (target.x - glideFrom.x) * e,
                     y: glideFrom.y + (target.y - glideFrom.y) * e)
        return true
    }

    private func cancelGlide() {
        ticker?.cancel()
        ticker = nil
        glideTo = nil
    }
}
