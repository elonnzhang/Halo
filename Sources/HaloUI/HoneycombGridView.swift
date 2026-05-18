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

    @State private var pinchBaseline: CGFloat = 1.0
    @State private var dragBaseline: CGSize = .zero
    @State private var commitPulse: Bool = false
    @State private var dragOffsets: [String: CGSize] = [:]
    @State private var cellFrames: [String: CGRect] = [:]
    /// Drives the cascade-in animation. 0 = pre-summon, 1 = settled.
    @State private var appearProgress: Double = 0

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
                searchChip(in: proxy.size)
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
            }
            .onAppear {
                pinchBaseline = gridState.zoomLevel
                dragBaseline = gridState.panOffset
                appearProgress = 0
                // Spring lets the cluster settle with a hint of bounce
                // — purposeful but brief, per Apple Motion guidelines.
                withAnimation(reduceMotion
                    ? .linear(duration: 0.001)
                    : .spring(response: 0.48, dampingFraction: 0.70)
                ) {
                    appearProgress = 1
                }
            }
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

    // MARK: - Grid geometry

    /// Centre icons land in the high-80s after focus lift; rim icons can
    /// fall into the mid-40s on large catalogues. That contrast is the
    /// watchOS read: a clear focal constellation instead of an even macOS
    /// icon sheet.
    public static let baseIconSize: CGFloat = 76
    /// Slightly roomy pitch so the enlarged centre can breathe while outer
    /// icons still feel clustered after fisheye pull-in.
    public static let baseSpacing: CGFloat = 100

    private var iconSize: CGFloat {
        Self.baseIconSize * gridState.zoomLevel * HaloUI.Geometry.panelScale
    }
    private var spacing: CGFloat {
        Self.baseSpacing * gridState.zoomLevel * HaloUI.Geometry.panelScale
    }
    private var verticalSpacingStretch: CGFloat { 1.18 }

    @ViewBuilder
    private func grid(in viewSize: CGSize) -> some View {
        let list = gridState.filteredApps
        let viewCentre = CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        let stripExclusion = stripExclusionRect(viewSize: viewSize)

        // Single origin shared by filter and render. Includes panOffset
        // so the lattice keep-out follows the TabBar through a pan —
        // the cluster's hex hole always sits under the strip rather
        // than drifting away with the pan.
        let estLayout = HoneycombGeometry.spiralLayout(count: list.count)
        let estBounds = HoneycombGeometry.layoutBounds(
            layout: estLayout,
            spacing: spacing,
            verticalStretch: verticalSpacingStretch
        )
        let originX = viewCentre.x - estBounds.midX + gridState.panOffset.width
        let originY = viewCentre.y - estBounds.midY + gridState.panOffset.height

        // Adaptive layout: apps whose natural spiral slot doesn't fall
        // in the keep-out stay there. Only the few apps right at the
        // boundary relocate to the nearest unused outer slot. So pan
        // moves the hole along with the TabBar while leaving 95%+ of
        // the cluster untouched, instead of cascading through every
        // app.
        let keepOut = stripExclusion?.insetBy(
            dx: -iconSize * 0.42,
            dy: -iconSize * 0.42
        )
        let layout = HoneycombGeometry.adaptiveSpiralLayout(
            count: list.count,
            spacing: spacing,
            verticalStretch: verticalSpacingStretch,
            keepOut: keepOut,
            originX: originX,
            originY: originY
        )

        // Stronger fisheye than a normal desktop grid: the focused core is
        // visibly larger, while dense catalogues compress the outer rings.
        let fisheyeRadius = min(viewSize.width, viewSize.height) * focusRadiusFactor(for: list.count)

        // One-cell padding cull. Cells whose centre lands well outside
        // the viewport aren't rendered. Generous so cells crossing in
        // / out of the cull rim during pan don't pop.
        let cullPad = spacing * 1.6
        let cullRect = CGRect(
            x: -cullPad,
            y: -cullPad,
            width: viewSize.width + 2 * cullPad,
            height: viewSize.height + 2 * cullPad
        )

        // Safety-net fade: adaptive layout already keeps cells out of
        // the keep-out rect, but fisheye projection can pull a cell a
        // few pt back toward focus. A small fade band along the strip
        // edges keeps any drift visually clean.
        let stripFadeBand: CGFloat = iconSize * 0.18

        let cells: [PositionedCell] = layout.enumerated().compactMap { idx, rc in
            let app = list[idx]
            let flat = HoneycombGeometry.center(
                row: rc.row,
                col: rc.col,
                spacing: spacing,
                verticalStretch: verticalSpacingStretch
            )
            let absolute = CGPoint(x: flat.x + originX, y: flat.y + originY)
            let focused = searchFocusedPosition(
                for: app,
                flatPosition: absolute,
                index: idx,
                viewCentre: viewCentre,
                query: gridState.searchQuery
            )
            guard cullRect.contains(focused) else { return nil }
            let stripFade = HoneycombGeometry.stripFadeOpacity(
                cellCenter: focused,
                strip: stripExclusion,
                band: stripFadeBand
            )
            return PositionedCell(app: app, position: focused, stripFade: stripFade)
        }
        let frameProjectionStrength: CGFloat = gridState.searchQuery.isEmpty ? 0.14 : 0.08
        let launchAnchor = gridState.committingBundleID.flatMap { committing in
            cells.first(where: { $0.id == committing })?.position
        }
        let nextFrames = cells.reduce(into: [String: CGRect]()) { partial, cell in
            let projection = HoneycombGeometry.fisheyeOffset(
                position: cell.position,
                viewCenter: viewCentre,
                maxRadius: fisheyeRadius,
                strength: frameProjectionStrength
            )
            let center = CGPoint(
                x: cell.position.x + projection.width,
                y: cell.position.y + projection.height
            )
            partial[cell.id] = CGRect(
                x: center.x - iconSize / 2,
                y: center.y - iconSize / 2,
                width: iconSize,
                height: iconSize
            )
        }

        ZStack {
            ForEach(cells, id: \.id) { cell in
                iconCell(
                    app: cell.app,
                    position: cell.position,
                    viewCentre: viewCentre,
                    fisheyeRadius: fisheyeRadius,
                    launchAnchor: launchAnchor,
                    stripFade: cell.stripFade
                )
                .transition(
                    .asymmetric(
                        insertion: .scale(scale: 0.88).combined(with: .opacity),
                        removal: .scale(scale: 0.92).combined(with: .opacity)
                    )
                )
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.78), value: gridState.searchQuery)
        .animation(reduceMotion ? nil : .spring(response: 0.24, dampingFraction: 0.74), value: gridState.apps)
        .opacity(gridState.committingBundleID == nil ? appearProgress : (commitPulse ? 0.96 : 0.12))
        .scaleEffect(0.78 + 0.22 * appearProgress)
        .onAppear { cellFrames = nextFrames }
        .onChange(of: gridState.filteredApps.map(\.bundleID)) { _ in cellFrames = nextFrames }
        .onChange(of: gridState.panOffset) { _ in cellFrames = nextFrames }
        .onChange(of: gridState.zoomLevel) { _ in cellFrames = nextFrames }
    }

    private func searchFocusedPosition(
        for app: GridState.GridApp,
        flatPosition: CGPoint,
        index: Int,
        viewCentre: CGPoint,
        query: String
    ) -> CGPoint {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return flatPosition }
        let normalized = q.lowercased()
        let matchStrength: CGFloat = app.name.lowercased().hasPrefix(normalized)
            || app.bundleID.lowercased().hasPrefix(normalized)
            ? 0.82
            : 0.58
        return HoneycombGeometry.searchAttractedPosition(
            flatPosition: flatPosition,
            viewCenter: viewCentre,
            index: index,
            strength: matchStrength
        )
    }


    @ViewBuilder
    private func gridAtmosphere(in viewSize: CGSize) -> some View {
        let active = gridState.selectedBundleID != nil || !gridState.searchQuery.isEmpty
        ZStack {
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

            SpecularArc(startAngleDegrees: -132, endAngleDegrees: -48)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0), Color.white.opacity(0.12), Color.white.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 1.1, lineCap: .round)
                )
                .frame(width: min(viewSize.width, viewSize.height) * 0.72,
                       height: min(viewSize.width, viewSize.height) * 0.72)
                .blur(radius: 0.4)
                .opacity(active ? 0.78 : 0.38)
        }
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
        let position: CGPoint
        /// Multiplier applied on top of the cell's normal opacity. 0
        /// when the cell has drifted under the TabBar during a pan, 1
        /// when it's safely outside the strip rect.
        let stripFade: Double
        var id: String { app.bundleID }
    }

    @ViewBuilder
    private func iconCell(
        app: GridState.GridApp,
        position: CGPoint,
        viewCentre: CGPoint,
        fisheyeRadius: CGFloat,
        launchAnchor: CGPoint?,
        stripFade: Double
    ) -> some View {
        let focusPoint = focusPoint(viewCentre: viewCentre)
        let distance = distance(from: position, to: focusPoint)
        let scale = projectedScale(for: position, viewCentre: viewCentre, fisheyeRadius: fisheyeRadius)
        let baseProjection = HoneycombGeometry.fisheyeOffset(
            position: position,
            viewCenter: focusPoint,
            maxRadius: fisheyeRadius,
            strength: gridState.searchQuery.isEmpty ? 0.12 : 0.06
        )
        let isSelected = gridState.selectedBundleID == app.bundleID
        let isCommitting = gridState.committingBundleID == app.bundleID
        let isDragging = gridState.draggingBundleID == app.bundleID
        let isDropTarget = gridState.dropTargetBundleID == app.bundleID
        let isCommitDimming = gridState.committingBundleID != nil && !isCommitting
        let commitPull: CGSize = {
            guard let launchAnchor, isCommitDimming else { return .zero }
            return HoneycombGeometry.commitCollapseOffset(
                position: position,
                anchor: launchAnchor,
                maxDistance: fisheyeRadius,
                strength: commitPulse ? 0.06 : 0.18
            )
        }()
        let hoverPush: CGSize = {
            guard let selected = gridState.selectedBundleID,
                  selected != app.bundleID,
                  let selectedFrame = cellFrames[selected]
            else { return .zero }
            // Subtle nudge only — the lattice already keeps a clean
            // grid, and a stronger repel made the whole cluster jitter
            // every time the cursor moved between cells.
            return HoneycombGeometry.hoverRepelOffset(
                position: position,
                hoverCenter: CGPoint(x: selectedFrame.midX, y: selectedFrame.midY),
                radius: iconSize * 1.05,
                strength: 1.6
            )
        }()
        let projection = CGSize(
            width: baseProjection.width + commitPull.width + hoverPush.width,
            height: baseProjection.height + commitPull.height + hoverPush.height
        )
        // Default: labels hide so long names don't visually overlap
        // their neighbours. During search the centre gets a watchOS-
        // style readable strip — matched cells are pulled close to the
        // focal point, so a centre-bright distance fade automatically
        // shows just the matches without crowding the rim.
        let labelOpacity: Double = gridState.searchQuery.isEmpty
            ? 0
            : pow(max(0, 1 - distance / fisheyeRadius), 1.65)

        IconCell(
            bundleID: app.bundleID,
            name: app.name,
            baseSize: iconSize,
            isSelected: isSelected,
            isCommitting: isCommitting,
            isDragging: isDragging,
            isDropTarget: isDropTarget,
            isCommitDimming: isCommitDimming,
            labelOpacity: labelOpacity,
            projectedScale: scale
        )
        .scaleEffect(scale * cellExtraScale(isSelected: isSelected, isCommitting: isCommitting, isDragging: isDragging))
        .opacity(stripFade * (isCommitDimming ? (commitPulse ? 0.58 : 0.08) : cellOpacity(distance: distance, radius: fisheyeRadius, isSelected: isSelected, isDragging: isDragging)))
        .allowsHitTesting(stripFade > 0.5)
        .offset(dragOffsets[app.bundleID] ?? .zero)
        .position(
            x: position.x + projection.width,
            y: position.y + projection.height
        )
        .zIndex(isCommitting ? 100 : (isDragging ? 80 : (isSelected ? 10 : 0)))
        .animation(reduceMotion ? nil : .spring(response: 0.13, dampingFraction: 0.68), value: isSelected)
        .animation(reduceMotion ? nil : .spring(response: 0.22, dampingFraction: 0.82), value: isDropTarget)
        .animation(reduceMotion ? nil : .timingCurve(0.2, 0.7, 0.2, 1, duration: 0.18), value: gridState.committingBundleID)
        .onHover { hovering in
            // Drag in progress: ignore hover changes from other cells.
            // Without this gate the cursor passing over neighbours flips
            // selectedBundleID off the dragged icon and back many times
            // per second, firing the isSelected spring on multiple cells
            // and oscillating hoverPush — visible as drag jitter.
            guard gridState.draggingBundleID == nil else { return }
            if hovering {
                gridState.selectedBundleID = app.bundleID
            } else if gridState.selectedBundleID == app.bundleID {
                gridState.selectedBundleID = nil
            }
        }
        .highPriorityGesture(iconDragGesture(for: app, from: position))
        .onTapGesture {
            guard gridState.draggingBundleID == nil else { return }
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
        return CGPoint(x: viewCentre.x, y: viewCentre.y - iconSize * 0.18)
    }

    private func projectedScale(
        for position: CGPoint,
        viewCentre: CGPoint,
        fisheyeRadius: CGFloat
    ) -> CGFloat {
        let focus = focusPoint(viewCentre: viewCentre)
        let distance = distance(from: position, to: focus)
        let dynamicMinScale = minimumScale(for: gridState.filteredApps.count)
        let baseScale = HoneycombGeometry.fisheyeScale(
            distance: distance,
            maxRadius: fisheyeRadius,
            minScale: gridState.searchQuery.isEmpty ? dynamicMinScale : 0.70,
            curve: 1.16
        )
        let centreLift = 1 + centerLift(for: gridState.filteredApps.count)
            * pow(max(0, 1 - distance / max(fisheyeRadius, 1)), 1.08)
        return baseScale * centreLift
    }

    private func cellFootprint(iconScale scale: CGFloat) -> CGSize {
        // Footprint used by the strip collision guard. Sized to just the
        // icon (with a small shadow allowance) — labels are hidden for
        // rim cells, so padding for them would make the guard push
        // boundary cells outward into their own neighbours.
        let icon = iconSize * scale
        return CGSize(width: icon * 1.06, height: icon * 1.06)
    }

    private func distance(from lhs: CGPoint, to rhs: CGPoint) -> CGFloat {
        let dx = lhs.x - rhs.x
        let dy = lhs.y - rhs.y
        return (dx * dx + dy * dy).squareRoot()
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
                    gridState.moveApp(bundleID: app.bundleID, near: target)
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

    /// Maximum pan offset allowed on each axis. Panning stops the moment
    /// the last icon's visual edge would disappear past the viewport boundary.
    ///
    /// Derivation (rightward pan; same logic applies to all four directions):
    ///   The renderer places the leftmost cell centre at:
    ///     x = viewCentre.x - estBounds.width/2 + panOffset.width
    ///   "Last icon disappears" means its centre (+ half icon width) exits
    ///   the right edge of the screen:
    ///     viewCentre.x - clusterHalfW + panOffset.width + iconSize/2 > viewSize.width
    ///   Rearranging for the last allowed panOffset:
    ///     maxX = viewSize.width/2 + clusterHalfW - iconSize/2
    ///              ≡ viewSize.width/2 + estBounds.width/2 - iconSize/2
    ///
    ///   Note: `estBounds` contains cell-centre coordinates only, so we add
    ///   iconSize/2 rather than iconSize — the icon's far edge extends half
    ///   an icon beyond its centre.
    private func panLimits(in viewSize: CGSize) -> (maxX: CGFloat, maxY: CGFloat) {
        let count = max(gridState.filteredApps.count, 1)
        let estLayout = HoneycombGeometry.spiralLayout(count: count)
        let estBounds = HoneycombGeometry.layoutBounds(
            layout: estLayout,
            spacing: spacing,
            verticalStretch: verticalSpacingStretch
        )
        return (
            maxX: max(0, viewSize.width  / 2 + estBounds.width  / 2 - iconSize / 2),
            maxY: max(0, viewSize.height / 2 + estBounds.height / 2 - iconSize / 2)
        )
    }

    private func clampPanOffset(in viewSize: CGSize) {
        let limits = panLimits(in: viewSize)
        let clamped = CGSize(
            width:  max(-limits.maxX, min(limits.maxX,  gridState.panOffset.width)),
            height: max(-limits.maxY, min(limits.maxY, gridState.panOffset.height))
        )
        guard clamped != gridState.panOffset else { return }
        gridState.panOffset = clamped
        dragBaseline = clamped
    }

    private func panGesture(in viewSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                guard gridState.draggingBundleID == nil else { return }
                // Recompute limits every event so zoom changes and
                // app-count changes (search) are always reflected.
                let limits = panLimits(in: viewSize)
                let proposed = CGSize(
                    width:  dragBaseline.width  + value.translation.width,
                    height: dragBaseline.height + value.translation.height
                )
                gridState.panOffset = CGSize(
                    width:  max(-limits.maxX, min(limits.maxX, proposed.width)),
                    height: max(-limits.maxY, min(limits.maxY, proposed.height))
                )
            }
            .onEnded { _ in
                dragBaseline = gridState.panOffset
            }
    }

    private func zoomGesture(in viewSize: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { mag in
                let next = pinchBaseline * mag
                gridState.zoomLevel = max(0.5, min(2.5, next))
            }
            .onEnded { _ in
                pinchBaseline = gridState.zoomLevel
                // Zoom changes cluster size → re-clamp so an out-zoomed
                // cluster doesn't leave panOffset beyond the new limits.
                clampPanOffset(in: viewSize)
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
    let projectedScale: CGFloat

    @State private var image: NSImage?

    var body: some View {
        VStack(spacing: 6) {
            iconStack
            label
        }
        .frame(width: baseSize + 34, height: baseSize + 24, alignment: .top)
        .task(id: bundleID) {
            self.image = AppIconResolver.icon(for: bundleID)
        }
    }

    @ViewBuilder
    private var iconStack: some View {
        ZStack {
            iconImage
                .frame(width: baseSize, height: baseSize)
                .shadow(color: .black.opacity(isDragging ? 0.32 : 0.24), radius: isDragging ? 12 : 5, y: isDragging ? 7 : 2)
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
            .shadow(color: .black.opacity(0.42), radius: 2, y: 1)
    }

    private var labelVisibility: Double {
        // Always show on direct interaction.
        if isSelected || isDragging { return 1.0 }
        // Search active → use the centre-bright fade passed in from
        // the parent so matches (pulled toward focus) get readable
        // labels and rim non-matches stay clean.
        if labelOpacity > 0 { return labelOpacity }
        // Default: only large centre icons get a label. Rim icons go
        // label-less so long names don't crowd neighbours, matching
        // watchOS Home Screen's clean periphery.
        if projectedScale >= 0.94 { return 1.0 }
        if projectedScale >= 0.86 { return Double((projectedScale - 0.86) / 0.08) }
        return 0
    }
}
