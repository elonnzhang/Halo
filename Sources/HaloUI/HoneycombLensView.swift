import AppKit
import SwiftUI
import HaloCore

/// ALL renderer: the onevra lens honeycomb. Dragging or scrolling pans a
/// point of the honeycomb under the middle of the view; it then settles with
/// the nearest app centred and selected. Hovering an app selects it; clicking
/// opens it. Apps that would rest under the profile strip move aside.
struct HoneycombLensView: View {
    @ObservedObject var gridState: GridState
    @ObservedObject var lens: HoneycombLensModel
    /// Tilt, ellipse ratio and edge fade come from Settings → General → Appearance.
    @ObservedObject private var prefs = AppPreferences.shared
    /// True while the grid panel is on screen. The hosting view survives
    /// orderOut, so re-entry resyncs here rather than in onAppear.
    let active: Bool
    let appear: Double
    let strip: CGRect?
    let onCommit: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(gridState: GridState, active: Bool, appear: Double, strip: CGRect?,
         onCommit: @escaping () -> Void) {
        self.gridState = gridState
        self.lens = gridState.lens
        self.active = active
        self.appear = appear
        self.strip = strip
        self.onCommit = onCommit
    }

    /// onevra sizes a 400×240 widget. Scale its lengths so the cell pitch
    /// matches the flat sheet's 100pt at full-screen size.
    /// The lens is an ellipse of the screen's proportions unless the user
    /// sets a ratio.
    private func metrics(for size: CGSize) -> HoneycombLensGeometry.Metrics {
        HoneycombLensGeometry.Metrics.scaled(
            HoneycombViewportGeometry.baseSpacing / 66 * HaloUI.Geometry.panelScale, viewSize: size,
            ratio: prefs.lensEllipseAuto ? nil : prefs.lensEllipseRatio,
            maxTilt: prefs.lensTilt)
    }

    private struct Cell: Identifiable {
        let index: Int
        let app: GridState.GridApp
        let placement: HoneycombLensGeometry.Placement
        let fade: Double
        /// Strip occlusion alone; rim dimming never blocks a click.
        let stripFade: Double
        var id: String { app.bundleID }
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let lensMetrics = metrics(for: size)
            let centre = HoneycombLensGeometry.lensCentre(
                viewSize: size, strip: strip, clearance: lensMetrics.large / 2 + 8)
            let cells = visibleCells(in: size, centre: centre, metrics: lensMetrics)
            let frames = hoverFrames(cells)
            let reservation = HoneycombLensModel.Reservation(viewSize: size, centre: centre, strip: strip)
            let middle = HoneycombLensGeometry.nearest(in: lens.cells, to: lens.at)
            ZStack {
                ForEach(cells) { cell in
                    let selected = gridState.selectedBundleID == cell.app.bundleID
                    LensIcon(bundleID: cell.app.bundleID, name: cell.app.name,
                             placement: cell.placement, ringed: selected,
                             lifted: selected && cell.index != middle,
                             ringWidth: lensMetrics.ring,
                             isCommitting: gridState.committingBundleID == cell.app.bundleID,
                             onActivate: { launch(cell.app.bundleID) })
                        .opacity(cell.fade * appear * commitOpacity(for: cell.app.bundleID))
                        .position(cell.placement.center)
                }
            }
            .frame(width: size.width, height: size.height)
            .scaleEffect(reduceMotion ? 1 : 0.94 + 0.06 * appear)
            .contentShape(Rectangle())
            .gesture(dragGesture(cells: cells))
            .onAppear {
                syncModel(lensMetrics)
                lens.reserve(reservation)
                gridState.cellFrames = frames
            }
            .onChange(of: active) { visible in
                guard visible else { return }
                syncModel(lensMetrics)
                lens.reserve(reservation)
            }
            .onChange(of: lensMetrics) { syncModel($0) }
            // Off screen (a first scan landing after the user left ALL) the
            // rebuild waits for the next entry, which resyncs through `active`.
            .onChange(of: gridState.filteredApps.map(\.bundleID)) { _ in
                guard active else { return }
                syncModel(lensMetrics)
            }
            .onChange(of: reservation) { lens.reserve($0) }
            // Hover hit-testing (HaloGridWindow) reads the rendered frames.
            .onChange(of: frames) { gridState.cellFrames = $0 }
        }
    }

    private func syncModel(_ metrics: HoneycombLensGeometry.Metrics) {
        PerfSignpost.measure("lensSync") {
            lens.sync(ids: gridState.filteredApps.map(\.bundleID), metrics: metrics)
        }
    }

    /// Only clickable icons are hoverable: none under the strip.
    private func hoverFrames(_ cells: [Cell]) -> [String: CGRect] {
        cells.reduce(into: [String: CGRect]()) { frames, cell in
            guard cell.stripFade > 0.5, cell.placement.opacity > 0.15 else { return }
            let p = cell.placement
            frames[cell.id] = CGRect(x: p.center.x - p.size / 2, y: p.center.y - p.size / 2,
                                     width: p.size, height: p.size)
        }
    }

    private func visibleCells(in size: CGSize, centre: CGPoint,
                              metrics: HoneycombLensGeometry.Metrics) -> [Cell] {
        let apps = gridState.filteredApps
        guard apps.count == lens.cells.count else { return [] }
        let rimRadius = min(size.width, size.height)
            * HoneycombGeometry.focusRadiusFactor(count: apps.count)
        return PerfSignpost.measure("lensProject") {
            lens.cells.enumerated().compactMap { index, point in
                let placement = HoneycombLensGeometry.place(
                    cell: point, at: lens.at, viewSize: size, metrics: metrics, centre: centre)
                guard placement.opacity > 0.01 else { return nil }
                // ALL's rim dimming, measured over the same elliptical lens.
                let dx = (placement.center.x - centre.x) / metrics.stretch.width
                let dy = (placement.center.y - centre.y) / metrics.stretch.height
                let rim = HoneycombGeometry.rimOpacity(
                    distance: hypot(dx, dy), radius: rimRadius, depth: prefs.lensRimFade)
                let half = placement.size / 2
                let fade = HoneycombGeometry.stripFadeOpacity(
                    cellCenter: placement.center,
                    strip: strip?.insetBy(dx: -half, dy: -half),
                    band: max(8, half * 0.7))
                return Cell(index: index, app: apps[index], placement: placement,
                            fade: Double(placement.opacity) * fade * rim, stripFade: fade)
            }
        }
    }

    private func commitOpacity(for bundleID: String) -> Double {
        guard let committing = gridState.committingBundleID else { return 1 }
        return committing == bundleID ? 1 : 0.12
    }

    private func dragGesture(cells: [Cell]) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard gridState.committingBundleID == nil else { return }
                lens.drag(to: value.location)
            }
            .onEnded { value in
                guard lens.endDrag() else { return }
                let hits = cells.filter { $0.stripFade > 0.5 }.map { ($0.index, $0.placement) }
                guard let index = HoneycombLensGeometry.hit(hits, at: value.location),
                      index < lens.ids.count else { return }
                // Open where it is: centring first could slide the app under
                // the profile strip, where it can no longer be clicked.
                launch(lens.ids[index])
            }
    }

    /// Click and VoiceOver press share one launch path.
    private func launch(_ bundleID: String) {
        guard gridState.committingBundleID == nil else { return }
        lens.stop()
        gridState.selectedBundleID = bundleID
        onCommit()
    }
}

/// Native app icon placed on the ball: squashed along its radial direction
/// with one affine transform, never a per-frame mask.
private struct LensIcon: View {
    let bundleID: String
    let name: String
    let placement: HoneycombLensGeometry.Placement
    let ringed: Bool
    /// Hovered but not centred: a small lift, as in the flat sheet.
    let lifted: Bool
    let ringWidth: CGFloat
    let isCommitting: Bool
    /// VoiceOver's press opens the app, as a click does.
    let onActivate: () -> Void
    @State private var image: NSImage?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let side = placement.size
        ZStack {
            if let image {
                Image(nsImage: image).resizable().interpolation(.medium)
                    .aspectRatio(contentMode: .fit)
            } else {
                RoundedRectangle(cornerRadius: side * 0.22, style: .continuous)
                    .fill(Color.white.opacity(0.08))
            }
            RoundedRectangle(cornerRadius: side * 0.24, style: .continuous)
                .strokeBorder(Color.accentColor.opacity(ringed ? 0.5 : 0), lineWidth: ringWidth)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.21), value: ringed)
        }
        .frame(width: side, height: side)
        .transformEffect(squash(side: side))
        .scaleEffect(isCommitting ? 1.12 : (lifted ? 1.08 : 1))
        .animation(reduceMotion ? nil : .spring(response: 0.16, dampingFraction: 0.88), value: lifted)
        .animation(reduceMotion ? nil : .timingCurve(0.2, 0.7, 0.2, 1, duration: 0.18), value: isCommitting)
        .task(id: bundleID) { image = AppIconResolver.icon(for: bundleID) }
        .accessibilityLabel(Text(name))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onActivate() }
    }

    /// M = I + (s - 1) u uᵀ about the icon centre, u the radial unit vector.
    private func squash(side: CGFloat) -> CGAffineTransform {
        let s = placement.squash
        guard s < 0.999 else { return .identity }
        let c = cos(placement.angle), n = sin(placement.angle), k = s - 1
        let m = CGAffineTransform(a: 1 + k * c * c, b: k * c * n,
                                  c: k * c * n, d: 1 + k * n * n, tx: 0, ty: 0)
        let half = side / 2
        return CGAffineTransform(translationX: -half, y: -half)
            .concatenating(m)
            .concatenating(CGAffineTransform(translationX: half, y: half))
    }
}
