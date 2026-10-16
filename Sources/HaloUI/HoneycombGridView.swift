import AppKit
import SwiftUI
import HaloCore

/// Full-screen watchOS-inspired Launchpad renderer.
///
/// Lays out installed apps into a near-square hexagonal cluster with
/// soft fisheye focus toward the centre. Built to feel like watchOS
/// Home Screen translated to Mac, not a literal port — the cluster has
/// macOS-typical density (7-9 columns, 64pt icons), keeps each app's
/// native icon (no forced circle clip), and supports keyboard search
/// + arrow navigation in addition to mouse / trackpad.
///
/// Layout
/// ------
/// Apps after the search filter sit at honeycomb (row, col) positions.
/// The lattice's geometric centre is translated to the view centre
/// plus `panOffset`. A fisheye function shrinks + nudges icons toward
/// the rim to create watchOS-style spatial focus.
///
/// Composition
/// -----------
/// 1. Subtle Liquid Glass backdrop (real `NSVisualEffectView` so blend
///    modes work in the non-activating panel).
/// 2. The icon cluster.
/// 3. Optional search chip (top-centre, only when query non-empty).
/// 4. Optional selected-app name (just above ProfileTabBar).
/// 5. ProfileTabBar — locked to the wheel's pre-grid screen position
///    so toggling between wheel and grid leaves it visually still.
public struct HoneycombGridView: View {
    @ObservedObject var state: HaloState
    @ObservedObject var gridState: GridState
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @StateObject private var layoutCache = HoneycombLayoutCache()
    @State private var pinchBaseline: CGFloat = 1.0
    @State private var dragBaseline: CGSize = .zero
    @State private var isPanning = false
    @State private var isPinching = false
    @State private var commitPulse: Bool = false
    @State private var dragOffsets: [String: CGSize] = [:]
    @State private var cellFrames: [String: CGRect] = [:]
    /// Drives the cascade-in animation. 0 = pre-summon, 1 = settled.
    @State private var appearProgress: Double = 0
    @State private var isEntering = false
    @State private var entryTask: Task<Void, Never>?
    /// True while a pan / pinch gesture is in flight (or just settled).
    /// Heavy SwiftUI modifiers (shadow blur, label shadow) are degraded
    /// to zero-radius while this is true so each IconCell render skips
    /// the offscreen blur pass — the dominant cost at high zoom where
    /// big icons multiply N shadow passes per frame.
    @State private var isInteracting: Bool = false
    @State private var interactionIdleTask: Task<Void, Never>?
    /// Viewport (pan, zoom) at which the profile-strip hole was last
    /// reserved. It stays fixed during motion so slots never teleport, then
    /// catches up once the viewport settles: the vacated hole refills and
    /// icons now under the strip move aside.
    @State private var stripAnchorPan: CGSize = .zero
    @State private var stripAnchorZoom: CGFloat = 1
    @State private var stripSettleTask: Task<Void, Never>?

    public init(state: HaloState) {
        self.state = state
        self.gridState = state.gridState
    }

    public var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                backdrop
                gridAtmosphere(in: proxy.size)
                if gridState.isLoading && gridState.apps.isEmpty {
                    loadingHint
                } else {
                    grid(in: proxy.size)
                }
                appCenterHeader
                searchChip(in: proxy.size)
                selectionBadge(in: proxy.size)
                profileStripOverlay(viewSize: proxy.size)
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .contentShape(Rectangle())
            .gesture(panGesture(in: proxy.size))
            .gesture(zoomGesture(in: proxy.size))
            // Reactive safety net: clamp panOffset whenever it changes
            // from any source (external state, zoom end, etc.).
            .onChange(of: gridState.panOffset) { _ in
                clampPanOffset(in: proxy.size)
                bumpInteraction()
            }
            // Wheel zoom mutates zoomLevel directly on GridState (bypassing
            // the pinch gesture); keep pinchBaseline in sync and re-clamp
            // pan so the resized cluster can't leave the pan beyond limits.
            .onChange(of: gridState.zoomLevel) { newValue in
                if !isPinching { pinchBaseline = newValue }
                clampPanOffset(in: proxy.size)
                // Wheel zoom relayouts per event; drop shadow blur during
                // the burst so a fast spin stays smooth (auto-clears 120ms
                // after the last notch).
                bumpInteraction()
            }
            .onChange(of: gridState.isViewportMoving) { moving in
                // A spring may remain active after its visible value reaches
                // a zoom bound. Its final tick need not change zoomLevel.
                if !moving, !isEntering, !isInteracting {
                    gridState.pointerSelectionSuppressed = false
                }
                if !moving { scheduleStripSettle() }
            }
            .onChange(of: isInteracting) { interacting in
                if !interacting { scheduleStripSettle() }
            }
            .onAppear {
                pinchBaseline = gridState.zoomLevel
                dragBaseline = gridState.panOffset
                if state.isGridMode { animateEntry() }
            }
            .onChange(of: state.isGridMode) { visible in
                if visible { animateEntry() }
                else {
                    stopInteraction()
                    stripAnchorPan = .zero
                    stripAnchorZoom = 1
                }
            }
            .onChange(of: gridState.apps.isEmpty) { empty in
                if !empty, state.isGridMode { animateEntry() }
            }
            .onChange(of: gridState.searchQuery) { _ in
                gridState.endViewportGesture()
                isPanning = false
                isPinching = false
                gridState.panOffset = .zero
                dragBaseline = .zero
                bumpInteraction()
            }
            .onChange(of: reduceMotion) { enabled in
                if enabled {
                    stopInteraction()
                    appearProgress = 1
                }
            }
            .onDisappear { stopInteraction() }
            .onChange(of: gridState.committingBundleID) { id in
                guard id != nil else { commitPulse = false; return }
                if reduceMotion {
                    commitPulse = true
                    return
                }
                commitPulse = false
                withAnimation(.easeOut(duration: 0.075)) {
                    commitPulse = true
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    withAnimation(.timingCurve(0.4, 0, 0.7, 0.2, duration: 0.12)) {
                        commitPulse = false
                    }
                }
            }
        }
    }

    // MARK: - Backdrop

    /// Light Liquid Glass — `NSVisualEffectView` blurs the wallpaper
    /// behind so the cluster reads with focus, but the mask is gentle
    /// (≈18 % black) so the wheel ↔ grid cross-fade still feels
    /// continuous rather than "open a new layer". A radial vignette
    /// pulls focus toward the centre without darkening foreground
    /// icons (rendered above this layer).
    @ViewBuilder
    private var backdrop: some View {
        ZStack {
            VisualEffectBackground(
                material: .hudWindow,
                blendingMode: .behindWindow,
                state: .active,
                emphasized: true
            )
            .opacity(0.78)
            Color.black.opacity(0.28)
            LinearGradient(
                colors: [
                    Color.white.opacity(0.035),
                    Color.black.opacity(0.04),
                    Color.black.opacity(0.18),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .blendMode(.softLight)
            RadialGradient(
                colors: [Color.black.opacity(0.0), Color.black.opacity(0.34)],
                center: .center,
                startRadius: 260,
                endRadius: 1040
            )
            .blendMode(.multiply)
        }
        .ignoresSafeArea()
    }

    @ViewBuilder
    private var loadingHint: some View {
        VStack(spacing: 12) {
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.large)
            Text("Indexing applications...")
                .font(.system(size: 13))
                .foregroundStyle(Color.white.opacity(0.7))
        }
    }

    @ViewBuilder
    private var appCenterHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 13, weight: .semibold))
            VStack(alignment: .leading, spacing: 0) {
                Text("App Center")
                    .font(.system(size: 12, weight: .semibold))
                if !gridState.apps.isEmpty {
                    Text(String.localizedStringWithFormat(
                        NSLocalizedString("%d apps", comment: "App Center catalogue count"),
                        gridState.apps.count
                    ))
                        .font(.system(size: 10, weight: .medium).monospacedDigit())
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
        }
        .foregroundStyle(Color.white.opacity(0.88))
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
        .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.10), lineWidth: 0.6))
        .padding(.top, 24)
        .padding(.leading, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .allowsHitTesting(false)
    }

    // MARK: - Grid geometry

    /// Centre icons land in the high-80s after focus lift; rim icons can
    /// fall into the mid-40s on large catalogues. That contrast is the
    /// watchOS read: a clear focal constellation instead of an even macOS
    /// icon sheet.
    public static let baseIconSize = HoneycombViewportGeometry.baseIconSize
    public static let baseSpacing = HoneycombViewportGeometry.baseSpacing

    private var canonicalIconSize: CGFloat { Self.baseIconSize * HaloUI.Geometry.panelScale }
    private var iconSize: CGFloat { canonicalIconSize * gridState.zoomLevel }
    private var canonicalSpacing: CGFloat {
        let base = Self.baseSpacing * HaloUI.Geometry.panelScale
        return gridState.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
            ? base : max(base, (canonicalIconSize + 48) * 1.08)
    }

    private func layout(in viewSize: CGSize) -> HoneycombViewportGeometry.Layout {
        let exclusion = HoneycombViewportGeometry.layoutExclusion(
            stripExclusionRect(viewSize: viewSize), viewSize: viewSize,
            pan: stripAnchorPan, zoom: stripAnchorZoom)
        return layoutCache.resolve(count: gridState.filteredApps.count,
                            spacing: canonicalSpacing, iconSize: canonicalIconSize,
                            viewSize: viewSize, exclusion: exclusion)
    }

    @ViewBuilder
    private func grid(in viewSize: CGSize) -> some View {
        let list = gridState.filteredApps
        let layout = layout(in: viewSize)
        let viewCentre = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        let focus = focusPoint(viewCentre: viewCentre)
        let stripExclusion = stripExclusionRect(viewSize: viewSize)
        let radius = min(viewSize.width, viewSize.height) * focusRadiusFactor(for: list.count)
        let searching = !gridState.searchQuery.trimmingCharacters(in: .whitespaces).isEmpty
        let cullPad = canonicalSpacing * gridState.zoomLevel * 1.5
        let cullRect = CGRect(origin: .zero, size: viewSize).insetBy(dx: -cullPad, dy: -cullPad)

        // Only this O(n) projection runs during gestures. Hex slot assignment,
        // bounds and the strip keep-out are cached at canonical zoom.
        let cells: [PositionedCell] = PerfSignpost.measure("watchViewportProject") {
            layout.offsets.enumerated().compactMap { index, offset in
                let projection = HoneycombViewportGeometry.project(
                    offset: offset, viewCenter: viewCentre, focus: focus,
                    pan: gridState.panOffset, zoom: gridState.zoomLevel, radius: radius,
                    minimumScale: searching ? 0.70 : minimumScale(for: list.count),
                    maximumScale: 1 + centerLift(for: list.count), pull: searching ? 0 : 0.12)
                // Cull after projection: a rim cell can be pulled into view.
                guard cullRect.contains(projection.center) else { return nil }
                let halfIcon = iconSize * projection.scale * 0.5
                let fade = HoneycombGeometry.stripFadeOpacity(
                    cellCenter: projection.center,
                    strip: stripExclusion?.insetBy(dx: -halfIcon, dy: -halfIcon),
                    band: max(12, halfIcon * 0.7))
                return PositionedCell(app: list[index], projection: projection, stripFade: fade)
            }
        }
        let launchAnchor = gridState.committingBundleID.flatMap { committing in
            cells.first(where: { $0.id == committing })?.position
        }

        ZStack {
            ForEach(cells) { cell in
                iconCell(app: cell.app, projection: cell.projection, viewCentre: viewCentre,
                         fisheyeRadius: radius, launchAnchor: launchAnchor, stripFade: cell.stripFade)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.94).combined(with: .opacity))
            }
        }
        .frame(width: viewSize.width, height: viewSize.height)
        .animation(.Halo.gridReflow(reduceMotion: reduceMotion), value: gridState.searchQuery)
        .animation(.Halo.gridReflow(reduceMotion: reduceMotion), value: gridState.apps)
        .opacity(gridState.committingBundleID == nil ? 1 : (commitPulse ? 0.96 : 0.12))
        .onAppear { refreshCellFrames(cells: cells, layout: layout, viewSize: viewSize) }
        .onChange(of: gridState.filteredApps.map(\.bundleID)) { _ in
            refreshCellFrames(cells: cells, layout: layout, viewSize: viewSize)
        }
        .onChange(of: gridState.panOffset) { _ in
            refreshCellFrames(cells: cells, layout: layout, viewSize: viewSize)
        }
        .onChange(of: gridState.zoomLevel) { _ in
            refreshCellFrames(cells: cells, layout: layout, viewSize: viewSize)
        }
        .onChange(of: stripExclusion) { _ in
            refreshCellFrames(cells: cells, layout: layout, viewSize: viewSize)
        }
        .onChange(of: stripAnchorPan) { _ in
            refreshCellFrames(cells: cells, layout: layout, viewSize: viewSize)
        }
        .onChange(of: stripAnchorZoom) { _ in
            refreshCellFrames(cells: cells, layout: layout, viewSize: viewSize)
        }
        .onChange(of: viewSize) { _ in
            refreshCellFrames(cells: cells, layout: layout, viewSize: viewSize)
        }
    }

    /// Hover, drag targets and rendering share the exact same lens projection
    /// and scaled icon footprint. Hidden strip cells are never hit-testable.
    private func refreshCellFrames(cells: [PositionedCell],
                                   layout: HoneycombViewportGeometry.Layout, viewSize: CGSize) {
        cellFrames = cells.reduce(into: [String: CGRect]()) { frames, cell in
            guard cell.stripFade > 0.5 else { return }
            frames[cell.id] = cell.projection.iconFrame(size: iconSize)
        }
        gridState.cellFrames = cellFrames
        gridState.viewportPanLimits = HoneycombViewportGeometry.panLimits(
            bounds: layout.bounds, viewSize: viewSize, zoom: gridState.zoomLevel, iconSize: iconSize)
    }

    @ViewBuilder
    private func gridAtmosphere(in viewSize: CGSize) -> some View {
        let active = gridState.selectedBundleID != nil || !gridState.searchQuery.isEmpty
        // The wheel pairs its specular arc with a halo rim so the
        // highlight reads as glass reflecting off a known edge. The
        // grid panel is full-screen with no rim, so dropping the same
        // arc in floats it as a free-standing curve in mid-air. Keep
        // just the soft centre glow.
        Circle()
            .fill(
                RadialGradient(
                    colors: [Color.white.opacity(active ? 0.10 : 0.055), Color.clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: min(viewSize.width, viewSize.height) * 0.38
                )
            )
            .frame(width: min(viewSize.width, viewSize.height) * 0.82)
            .blendMode(.plusLighter)
            .opacity(0.48)
            .position(x: viewSize.width / 2, y: viewSize.height / 2)
            .allowsHitTesting(false)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: active)
    }

    /// Bounding rect (in grid local coords) that the ProfileTabBar
    /// occupies, expanded by half an icon plus a few px so the cluster
    /// keeps a visible gap. `nil` when the strip isn't visible (single
    /// pill → ProfileTabBar renders nothing) so the grid uses the
    /// whole viewport.
    private func stripExclusionRect(viewSize: CGSize) -> CGRect? {
        guard state.profilePills.count > 1 else { return nil }
        let centre = stripScreenPosition(in: viewSize)
        // Width estimate matches the rendered pill row closely. Each
        // text pill is about 56pt wide (12pt SemiBold name + 24pt h-pad
        // + 4pt gap), and the ALL icon-only pill is ~32pt. Slightly
        // overshoot per pill so long profile names still fit, but
        // don't pad heavily — that just leaves dead space around the
        // strip in grid mode.
        let pillCount = max(state.profilePills.count, 2)
        let estimatedWidth = CGFloat(pillCount) * 58 + 8
        let estimatedHeight: CGFloat = 32
        // Tight margin — the lattice filter inflates this by half an
        // icon, which is the only buffer needed to keep icons from
        // visually touching the strip.
        let pad: CGFloat = 4
        return CGRect(
            x: centre.x - estimatedWidth / 2 - pad,
            y: centre.y - estimatedHeight / 2 - pad,
            width: estimatedWidth + 2 * pad,
            height: estimatedHeight + 2 * pad
        )
    }

    /// Carrier struct so the grid's ForEach can key off `bundleID`
    /// while still rendering the precomputed honeycomb position.
    private struct PositionedCell: Identifiable {
        let app: GridState.GridApp
        let projection: HoneycombViewportGeometry.Projection
        let stripFade: Double
        var position: CGPoint { projection.center }
        var id: String { app.bundleID }
    }

    @ViewBuilder
    private func iconCell(
        app: GridState.GridApp,
        projection: HoneycombViewportGeometry.Projection,
        viewCentre: CGPoint,
        fisheyeRadius: CGFloat,
        launchAnchor: CGPoint?,
        stripFade: Double
    ) -> some View {
        let position = projection.center
        let isSelected = gridState.selectedBundleID == app.bundleID
        let isCommitting = gridState.committingBundleID == app.bundleID
        let isDragging = gridState.draggingBundleID == app.bundleID
        let isDropTarget = gridState.dropTargetBundleID == app.bundleID
        let isCommitDimming = gridState.committingBundleID != nil && !isCommitting
        let commitPull: CGSize = {
            guard let launchAnchor, isCommitDimming else { return .zero }
            return HoneycombGeometry.commitCollapseOffset(
                position: position, anchor: launchAnchor, maxDistance: fisheyeRadius,
                strength: commitPulse ? 0.06 : 0.18)
        }()
        let hoverPush: CGSize = {
            guard !isInteracting, !gridState.isViewportMoving,
                  let selected = gridState.selectedBundleID, selected != app.bundleID,
                  let frame = cellFrames[selected] else { return .zero }
            return HoneycombGeometry.hoverRepelOffset(
                position: position, hoverCenter: CGPoint(x: frame.midX, y: frame.midY),
                radius: iconSize * 1.05, strength: 1.6)
        }()
        let labelOpacity: Double = gridState.searchQuery.isEmpty
            ? 0 : pow(max(0, 1 - projection.distance / max(fisheyeRadius, 1)), 1.65)
        let entryScale = reduceMotion ? 1 : 0.92 + 0.08 * appearProgress
        let entryDelay = min(Double(projection.distance / max(fisheyeRadius, 1)), 1) * 0.065

        IconCell(
            bundleID: app.bundleID, name: app.name, baseSize: iconSize,
            isSelected: isSelected, isCommitting: isCommitting, isDragging: isDragging,
            isDropTarget: isDropTarget, isCommitDimming: isCommitDimming,
            labelOpacity: labelOpacity,
            suppressShadows: (isInteracting || gridState.isViewportMoving || isEntering) && !isDragging
        )
        .scaleEffect(projection.scale * entryScale
                     * cellExtraScale(isSelected: isSelected, isCommitting: isCommitting, isDragging: isDragging))
        .animation(reduceMotion ? nil : .spring(response: 0.16, dampingFraction: 0.88), value: isSelected)
        .opacity(appearProgress * stripFade * (isCommitDimming ? (commitPulse ? 0.58 : 0.08)
                 : cellOpacity(distance: projection.distance, radius: fisheyeRadius,
                               isSelected: isSelected, isDragging: isDragging)))
        .allowsHitTesting(stripFade > 0.5)
        .offset(dragOffsets[app.bundleID] ?? .zero)
        .position(x: viewCentre.x + (position.x - viewCentre.x) * entryScale + commitPull.width + hoverPush.width,
                  y: viewCentre.y + (position.y - viewCentre.y) * entryScale + commitPull.height + hoverPush.height)
        .zIndex(isCommitting ? 100 : (isDragging ? 80 : (isSelected ? 10 : 0)))
        .animation(.Halo.gridEnter(delay: entryDelay, reduceMotion: reduceMotion), value: appearProgress)
        .animation(.Halo.gridReflow(reduceMotion: reduceMotion), value: isDropTarget)
        .animation(reduceMotion ? nil : .timingCurve(0.2, 0.7, 0.2, 1, duration: 0.18), value: gridState.committingBundleID)
        .onHover { hovering in
            guard gridState.draggingBundleID == nil, !isInteracting, !isEntering,
                  !gridState.isViewportMoving else { return }
            if hovering {
                if gridState.selectedBundleID != app.bundleID { gridState.selectedBundleID = app.bundleID }
            } else if gridState.selectedBundleID == app.bundleID {
                gridState.selectedBundleID = nil
            }
        }
        .highPriorityGesture(iconDragGesture(for: app, from: position))
        .onTapGesture {
            guard gridState.draggingBundleID == nil else { return }
            gridState.endViewportGesture()
            gridState.selectedBundleID = app.bundleID
            state.onCommit?()
        }
        .accessibilityLabel(Text(app.name))
        .accessibilityAddTraits(.isButton)
    }

    /// Combine selection lift (1.08) with commit burst (1.18 then
    /// 0.88 in the late phase). The second phase rides off
    /// `committingBundleID` flipping on; the panel fade-out follows
    /// ~150ms later so the user sees the burst before everything
    /// dissolves.
    private func cellExtraScale(isSelected: Bool, isCommitting: Bool, isDragging: Bool) -> CGFloat {
        if isCommitting { return commitPulse ? 1.16 : 0.92 }
        if isDragging { return 1.12 }
        if isSelected { return 1.11 }
        return 1.0
    }

    private func focusPoint(viewCentre: CGPoint) -> CGPoint {
        guard state.profilePills.count > 1 else { return viewCentre }
        return CGPoint(x: viewCentre.x, y: viewCentre.y - canonicalIconSize * 0.18)
    }

    private func minimumScale(for count: Int) -> CGFloat {
        switch count {
        case 0...34: return 0.72
        case 35...64: return 0.62
        case 65...104: return 0.54
        default: return 0.48
        }
    }

    private func centerLift(for count: Int) -> CGFloat {
        switch count {
        case 0...34: return 0.20
        case 35...64: return 0.24
        case 65...104: return 0.28
        default: return 0.31
        }
    }

    private func focusRadiusFactor(for count: Int) -> CGFloat {
        switch count {
        case 0...34: return 0.52
        case 35...64: return 0.48
        case 65...104: return 0.44
        default: return 0.40
        }
    }

    private func cellOpacity(distance: CGFloat, radius: CGFloat, isSelected: Bool, isDragging: Bool) -> Double {
        if isSelected || isDragging { return 1 }
        let t = min(max(distance / radius, 0), 1)
        let rim = 1 - 0.36 * Double(t * t)
        return max(0.52, rim)
    }

    private func iconDragGesture(for app: GridState.GridApp, from startPosition: CGPoint) -> some Gesture {
        DragGesture(minimumDistance: 9)
            .onChanged { value in
                // Only flip the @Published flags when the value actually
                // changes — assigning every frame fires objectWillChange
                // on the 100+ cell ZStack and turns drag into a slideshow.
                if gridState.draggingBundleID != app.bundleID {
                    gridState.endViewportGesture()
                    isPanning = false
                    gridState.draggingBundleID = app.bundleID
                }
                if gridState.selectedBundleID != app.bundleID {
                    gridState.selectedBundleID = app.bundleID
                }
                dragOffsets[app.bundleID] = value.translation
                let finger = CGPoint(
                    x: startPosition.x + value.translation.width,
                    y: startPosition.y + value.translation.height
                )
                let nearest = nearestBundleID(to: finger, excluding: app.bundleID)
                if gridState.dropTargetBundleID != nearest {
                    gridState.dropTargetBundleID = nearest
                }
            }
            .onEnded { _ in
                let target = gridState.dropTargetBundleID
                withAnimation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.82)) {
                    dragOffsets[app.bundleID] = .zero
                }
                if let target {
                    gridState.moveApp(bundleID: app.bundleID, near: target, reduceMotion: reduceMotion)
                }
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 90_000_000)
                    dragOffsets[app.bundleID] = nil
                    gridState.draggingBundleID = nil
                    gridState.dropTargetBundleID = nil
                }
            }
    }

    private func nearestBundleID(to point: CGPoint, excluding excludedID: String) -> String? {
        let threshold = max(38, iconSize * 0.68)
        var best: (id: String, distance: CGFloat)?
        for app in gridState.filteredApps where app.bundleID != excludedID {
            guard let frame = cellFrames[app.bundleID] else { continue }
            let center = CGPoint(x: frame.midX, y: frame.midY)
            let dx = center.x - point.x
            let dy = center.y - point.y
            let distance = (dx * dx + dy * dy).squareRoot()
            guard distance < threshold else { continue }
            if best == nil || distance < best!.distance {
                best = (app.bundleID, distance)
            }
        }
        return best?.id
    }


    // MARK: - Search chip

    /// Floating glass capsule that surfaces when the user types. The
    /// search query lives in `gridState.searchQuery`; AppDelegate's
    /// keyMonitor pipes alphanumeric / backspace keystrokes into it
    /// while in grid mode.
    @ViewBuilder
    private func searchChip(in viewSize: CGSize) -> some View {
        if !gridState.searchQuery.isEmpty {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .medium))
                Text(gridState.searchQuery)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                Text("\(gridState.filteredApps.count)")
                    .font(.system(size: 11, weight: .regular).monospacedDigit())
                    .foregroundStyle(Color.white.opacity(0.55))
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.white.opacity(0.10))
                    )
            }
            .foregroundStyle(Color.white.opacity(0.95))
            .padding(.horizontal, 16)
            .padding(.vertical, 9)
            .background(
                Capsule(style: .continuous)
                    .fill(.ultraThinMaterial)
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6)
            )
            .shadow(color: .black.opacity(0.45), radius: 10, y: 3)
            .padding(.top, 24)
            .frame(maxWidth: .infinity, alignment: .top)
            .frame(height: 80, alignment: .top)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .transition(.move(edge: .top).combined(with: .opacity))
            .animation(.easeOut(duration: 0.16), value: gridState.searchQuery)
            .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func selectionBadge(in viewSize: CGSize) -> some View {
        if let selectedID = gridState.selectedBundleID,
           let selected = gridState.apps.first(where: { $0.bundleID == selectedID }) {
            let badge = HStack(spacing: 8) {
                if let icon = AppIconResolver.icon(for: selected.bundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 22, height: 22)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(selected.name)
                        .font(.system(size: 13, weight: .semibold))
                        .lineLimit(1)
                    Text("Press Return to open")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.white.opacity(0.55))
                }
            }
            .foregroundStyle(Color.white.opacity(0.95))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Capsule(style: .continuous).fill(.ultraThinMaterial))
            .overlay(Capsule(style: .continuous).strokeBorder(Color.white.opacity(0.12), lineWidth: 0.6))
            .shadow(color: .black.opacity(0.36), radius: 8, y: 2)
            .fixedSize()
            .allowsHitTesting(false)

            // Fixed bottom-centre position (spec: "应用名称在下面固定
            // 显示"). The *content* already follows the cursor because
            // `selectedBundleID` is driven by each cell's `onHover`, so the
            // badge stays put while its name/icon update as the pointer
            // moves between apps.
            badge
                .padding(.bottom, 28)
                .frame(maxWidth: .infinity, alignment: .top)
                .frame(maxHeight: .infinity, alignment: .bottom)
                // Cross-fade the content on selection change instead of the
                // slide-up, so a moving cursor doesn't make the pill jump.
                .animation(.easeOut(duration: 0.10), value: selectedID)
        }
    }

    // MARK: - Profile strip overlay (locked to wheel position)

    @ViewBuilder
    private func profileStripOverlay(viewSize: CGSize) -> some View {
        let stripPos = stripScreenPosition(in: viewSize)
        // Wheel side scales the entire RadialView (incl. its own
        // ProfileTabBar) via `.scaleEffect(panelScale)` on the root.
        // Grid is full-screen so we can't scale the whole panel —
        // scale just the TabBar so it matches the wheel's strip
        // size when the user has a non-1.0 panelScale.
        ProfileTabBar(
            pills: state.profilePills,
            activeID: state.activeProfileID,
            onSwitch: { id in state.onSwitchProfile?(id) }
        )
        .scaleEffect(HaloUI.Geometry.panelScale)
        .position(stripPos)
        .allowsHitTesting(state.profilePills.count > 1)
    }

    private func stripScreenPosition(in viewSize: CGSize) -> CGPoint {
        let stripHalfHeight: CGFloat = 16
        let panelScale = HaloUI.Geometry.panelScale
        let stripOffsetCocoa = panelScale
            * (HaloUI.Geometry.totalDiameter / 2 - 18 - stripHalfHeight)

        let cocoaCentre = state.center
        guard cocoaCentre != .zero,
              let screen = NSScreen.screens.first(where: { $0.frame.contains(cocoaCentre) })
                ?? NSScreen.main
        else {
            return CGPoint(x: viewSize.width / 2, y: 30)
        }
        let vf = screen.visibleFrame
        let localX = cocoaCentre.x - vf.minX
        let localY = vf.maxY - cocoaCentre.y
        let placeBelow = state.edgeAnchor == .top
        let stripY = placeBelow
            ? localY + stripOffsetCocoa
            : localY - stripOffsetCocoa
        return CGPoint(x: localX, y: stripY)
    }

    // MARK: - Gestures

    /// Both input routes use the cached cluster extent, keeping the last
    /// icon on screen even when the reserved-strip layout is asymmetric.
    private func panLimits(in viewSize: CGSize) -> CGSize {
        HoneycombViewportGeometry.panLimits(bounds: layout(in: viewSize).bounds,
                                           viewSize: viewSize, zoom: gridState.zoomLevel, iconSize: iconSize)
    }

    private func clampPanOffset(in viewSize: CGSize) {
        let clamped = HoneycombViewportGeometry.clamp(gridState.panOffset, limits: panLimits(in: viewSize))
        guard clamped != gridState.panOffset else { return }
        gridState.panOffset = clamped
    }

    private func animateEntry() {
        entryTask?.cancel()
        isEntering = true
        gridState.pointerSelectionSuppressed = true
        var transaction = Transaction(animation: nil)
        transaction.disablesAnimations = true
        withTransaction(transaction) { appearProgress = 0 }
        entryTask = Task { @MainActor in
            // Ensure the collapsed state is rendered before opening. The
            // hosting view survives orderOut, so onAppear alone isn't enough.
            await Task.yield()
            guard !Task.isCancelled, state.isGridMode else { return }
            withAnimation(.Halo.gridEnter(reduceMotion: reduceMotion)) { appearProgress = 1 }
            do { try await Task.sleep(nanoseconds: reduceMotion ? 60_000_000 : 520_000_000) }
            catch { return }
            isEntering = false
            gridState.pointerSelectionSuppressed = isInteracting || gridState.isViewportMoving
        }
    }

    private func stopInteraction() {
        entryTask?.cancel()
        interactionIdleTask?.cancel()
        stripSettleTask?.cancel()
        gridState.endViewportGesture()
        gridState.pointerSelectionSuppressed = false
        isEntering = false
        isInteracting = false
        isPanning = false
        isPinching = false
    }

    private func bumpInteraction() {
        if !isInteracting { isInteracting = true }
        gridState.pointerSelectionSuppressed = true
        interactionIdleTask?.cancel()
        interactionIdleTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 120_000_000) }
            catch { return }
            isInteracting = false
            gridState.pointerSelectionSuppressed = isEntering || gridState.isViewportMoving
        }
    }

    /// Re-anchor the strip hole after pan/zoom has been idle briefly. One
    /// reflow per settle keeps motion itself slot-stable.
    private func scheduleStripSettle() {
        stripSettleTask?.cancel()
        guard state.profilePills.count > 1 else { return }
        stripSettleTask = Task { @MainActor in
            do { try await Task.sleep(nanoseconds: 160_000_000) }
            catch { return }
            guard state.isGridMode, !isInteracting, !gridState.isViewportMoving,
                  gridState.draggingBundleID == nil, gridState.committingBundleID == nil
            else { return }
            let pan = gridState.panOffset
            let zoom = gridState.zoomLevel
            guard pan != stripAnchorPan || zoom != stripAnchorZoom else { return }
            withAnimation(.Halo.gridReflow(reduceMotion: reduceMotion)) {
                stripAnchorPan = pan
                stripAnchorZoom = zoom
            }
        }
    }

    private func panGesture(in viewSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 3)
            .onChanged { value in
                guard gridState.draggingBundleID == nil else { return }
                if !isPanning {
                    gridState.beginViewportGesture()
                    dragBaseline = gridState.panOffset
                    isPanning = true
                }
                bumpInteraction()
                gridState.panOffset = HoneycombViewportGeometry.clamp(
                    CGSize(width: dragBaseline.width + value.translation.width,
                           height: dragBaseline.height + value.translation.height),
                    limits: panLimits(in: viewSize))
            }
            .onEnded { value in
                guard isPanning else { return }
                isPanning = false
                gridState.coastViewport(
                    by: CGSize(width: value.predictedEndTranslation.width - value.translation.width,
                               height: value.predictedEndTranslation.height - value.translation.height),
                    reduceMotion: reduceMotion)
                bumpInteraction()
            }
    }

    private func zoomGesture(in viewSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { mag in
                if !isPinching {
                    gridState.beginViewportGesture()
                    pinchBaseline = gridState.zoomLevel
                    isPinching = true
                }
                bumpInteraction()
                // Stable cached slots make continuous projection cheap. No
                // transient GPU scale to fold back into a different lens.
                gridState.zoomLevel = max(0.5, min(2.5, pinchBaseline * mag))
            }
            .onEnded { _ in
                isPinching = false
                pinchBaseline = gridState.zoomLevel
                gridState.endViewportGesture()
                clampPanOffset(in: viewSize)
                bumpInteraction()
            }
    }

}

// MARK: - Single icon cell

/// One app cell: native icon (no forced circle clip), Liquid-Glass
/// halo behind, name label below. Hover and commit states drive
/// scale + glow via the parent's animation modifiers.
private struct IconCell: View {
    let bundleID: String
    let name: String
    let baseSize: CGFloat
    let isSelected: Bool
    let isCommitting: Bool
    let isDragging: Bool
    let isDropTarget: Bool
    let isCommitDimming: Bool
    /// Distance-from-focus opacity for the label. 1.0 in centre,
    /// 0.0 at the fisheye rim; multiplied with the in-cell label
    /// modulation (selected = full opacity).
    let labelOpacity: Double
    /// Set by the parent while a pan/pinch is in flight. When true,
    /// the icon + label shadows render at radius 0 so SwiftUI skips
    /// the offscreen blur pass.
    let suppressShadows: Bool

    @State private var image: NSImage?

    var body: some View {
        iconStack
        .frame(width: baseSize, height: baseSize)
        .overlay(alignment: .bottom) { label.offset(y: 20) }
        .contentShape(Rectangle())
        .task(id: bundleID) {
            self.image = AppIconResolver.icon(for: bundleID)
        }
    }

    @ViewBuilder
    private var iconStack: some View {
        ZStack {
            iconImage
                .frame(width: baseSize, height: baseSize)
                // Shadow radius collapses to 0 while a pan / pinch is
                // in flight (`suppressShadows == true`). SwiftUI shadow
                // with non-zero radius forces an offscreen blur pass
                // per cell per frame; at high zoom with ~60 visible
                // cells that's the dominant cost. Zero-radius is a
                // cheap no-op and visually a single-frame loss only
                // while the user is mid-gesture.
                .shadow(
                    color: .black.opacity(isDragging ? 0.32 : 0.24),
                    radius: suppressShadows ? 0 : (isDragging ? 12 : 5),
                    y: suppressShadows ? 0 : (isDragging ? 7 : 2)
                )
                .brightness(isSelected || isDragging ? 0.045 : 0)
        }
    }

    @ViewBuilder
    private var iconImage: some View {
        if let nsImage = image {
            // Native macOS icon — no Circle clip. App icons already
            // ship with the platform's rounded-square shape; clipping
            // them to a circle was the watchOS literalism the user
            // wanted to avoid.
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
        } else {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.08))
        }
    }

    @ViewBuilder
    private var label: some View {
        Text(name)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.white.opacity(0.88))
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(width: baseSize + 48, height: 14)
            .minimumScaleFactor(0.82)
            .opacity(isCommitDimming ? 0.0 : labelVisibility)
            .shadow(
                color: .black.opacity(0.42),
                radius: suppressShadows ? 0 : 2,
                y: suppressShadows ? 0 : 1
            )
    }

    private var labelVisibility: Double {
        // Always show on direct interaction.
        if isSelected || isDragging { return 1.0 }
        // Search active → use the centre-bright fade passed in from
        // the parent so matches (pulled toward focus) get readable
        // labels and rim non-matches stay clean.
        if labelOpacity > 0 { return labelOpacity }
        // Keep the moving constellation clear. Names appear on hover or
        // during search; the fixed bottom badge also identifies selection.
        return 0
    }
}


/// One bounded cache per hosting view; no process-wide layout state.
@MainActor
private final class HoneycombLayoutCache: ObservableObject {
    private struct Key: Equatable {
        let count: Int
        let spacing: CGFloat
        let iconSize: CGFloat
        let viewSize: CGSize
        let exclusion: CGRect?
    }
    private var key: Key?
    private var cached: HoneycombViewportGeometry.Layout?

    func resolve(count: Int, spacing: CGFloat, iconSize: CGFloat,
                 viewSize: CGSize, exclusion: CGRect?) -> HoneycombViewportGeometry.Layout {
        let next = Key(count: count, spacing: spacing, iconSize: iconSize,
                       viewSize: viewSize, exclusion: exclusion)
        if key == next, let cached { return cached }
        let value = PerfSignpost.measure("watchLayout") {
            HoneycombViewportGeometry.layout(count: count, spacing: spacing, iconSize: iconSize,
                                             viewSize: viewSize, exclusion: exclusion)
        }
        key = next
        cached = value
        return value
    }
}
