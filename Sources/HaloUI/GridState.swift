import AppKit
import Foundation
import SwiftUI
import HaloCore

/// Source of truth for the watchOS-style honeycomb grid.
///
/// Owns:
/// - the catalogued list of installable apps (scanned once on first
///   activation, then reused across summons until invalidated);
/// - the user's transient zoom / pan state while the grid is on screen;
/// - which app the cursor (or keyboard) currently has selected so the
///   shared `commitSelection()` path can launch it.
///
/// `@MainActor` because every consumer (HaloState, HoneycombGridView,
/// AppDelegate.commitSelection) is already main-actor-isolated, and
/// SwiftUI's `@Published` integration assumes main-actor mutation.
@MainActor
public final class GridState: ObservableObject {
    /// One installed app surfaced into the grid. Sortable by name; the
    /// `bundleID` is the stable key for icon lookup + launch dispatch.
    public struct GridApp: Identifiable, Equatable, Sendable {
        public let bundleID: String
        public let name: String
        public let url: URL
        public let rank: Int
        public let usageScore: Double

        public var id: String { bundleID }

        public init(bundleID: String, name: String, url: URL, rank: Int = Int.max, usageScore: Double = 0) {
            self.bundleID = bundleID
            self.name = name
            self.url = url
            self.rank = rank
            self.usageScore = usageScore
        }
    }

    @Published public var apps: [GridApp] = [] {
        didSet { invalidateFilteredAppsCache() }
    }
    /// 1.0 = canonical layout. The view multiplies hex spacing + icon
    /// size by this. Bounds are enforced in the gesture path so the
    /// state itself stays "whatever you set," matching how `panOffset`
    /// is treated.
    @Published public var zoomLevel: CGFloat = 1.0
    /// Cumulative drag offset since the grid became visible. Reset on
    /// `resetViewport()` when leaving grid mode.
    @Published public var panOffset: CGSize = .zero
    /// Presentation motion is transient and scoped to this grid. Pointer
    /// selection pauses while icons move, so hovering cannot retarget springs
    /// underneath a drag, pinch, or wheel-zoom burst.
    @Published public internal(set) var isViewportMoving: Bool = false
    public var pointerSelectionSuppressed = false
    /// Updated by the renderer from its cached layout; native scroll and
    /// mouse drag share the same bounds instead of rebuilding the lattice.
    public var viewportPanLimits: CGSize = .zero
    private lazy var viewportMotion = GridViewportMotion(state: self)
    /// Bundle ID currently under the cursor (or selected via keyboard).
    /// `nil` while the user is between cells. `commitSelection()` reads
    /// this to decide what to launch.
    @Published public var selectedBundleID: String?
    /// True while `loadApps()` is in flight on a background actor. The
    /// view shows a placeholder so the first summon doesn't render an
    /// empty grid. Cleared as soon as `apps` is published.
    @Published public var isLoading: Bool = false
    /// Live search input. Updates filtered list + drives the search
    /// chip's appearance. Cleared on `resetViewport()`.
    @Published public var searchQuery: String = "" {
        didSet { invalidateFilteredAppsCache() }
    }
    /// Latches to true on commit so the view can play the launch
    /// burst before the panel fades. Resets on `resetViewport()`.
    @Published public var committingBundleID: String?
    /// Bundle ID currently being dragged in the grid. This is transient
    /// visual state only; persistence for a custom order/folders can be
    /// added later without changing the renderer's drag affordances.
    @Published public var draggingBundleID: String?
    /// Bundle ID under the dragged app. Rendered as a drop
    /// target, but not committed to storage yet.
    @Published public var dropTargetBundleID: String?

    /// Projected (post-fisheye) hit-test frames for the currently visible
    /// cells, in SwiftUI view coordinates (top-left origin, y-down). Written
    /// by the view's layout pass; read by the grid window's cursor-poll timer
    /// to resolve which app the pointer is over. Plain (not `@Published`) so
    /// updating it every layout doesn't churn the view.
    public var cellFrames: [String: CGRect] = [:]

    /// Resolve the hovered app from a cursor point (view coordinates) and set
    /// it as the selection so the bottom name badge follows the pointer.
    /// Picks the cell whose frame contains the point, else the nearest within
    /// a small radius. No-op while dragging.
    public func hoverSelect(at point: CGPoint, iconSize: CGFloat) {
        guard draggingBundleID == nil, !isViewportMoving, !pointerSelectionSuppressed else { return }
        var best: (id: String, d: CGFloat)?
        for app in filteredApps {
            let id = app.bundleID
            guard let frame = cellFrames[id] else { continue }
            let dx = frame.midX - point.x
            let dy = frame.midY - point.y
            let d = (dx * dx + dy * dy).squareRoot()
            if (frame.contains(point) || d < frame.width * 0.6), best == nil || d < best!.d {
                best = (id, d)
            }
        }
        let next = best?.id
        if selectedBundleID != next { selectedBundleID = next }
    }

    /// Apps after the search filter is applied. Empty query → full
    /// list; otherwise case-insensitive substring match against name
    /// then bundleID. Sort order is preserved.
    private var filteredAppsCache: [GridApp]?
    private var filteredAppsCacheQuery: String?

    public var filteredApps: [GridApp] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        if filteredAppsCacheQuery == query, let cached = filteredAppsCache {
            return cached
        }
        guard !query.isEmpty else {
            filteredAppsCacheQuery = query
            filteredAppsCache = apps
            return apps
        }
        let needle = query.lowercased()
        let filtered = apps.filter { app in
            app.name.lowercased().contains(needle)
                || app.bundleID.lowercased().contains(needle)
        }
        filteredAppsCacheQuery = query
        filteredAppsCache = filtered
        return filtered
    }

    private func invalidateFilteredAppsCache() {
        filteredAppsCache = nil
        filteredAppsCacheQuery = nil
    }

    public init() {}

    /// Asynchronously rescan `/Applications`, `/System/Applications`,
    /// and `~/Applications`, dedupe by bundle ID, and publish a
    /// name-sorted list. Idempotent: if `apps` is already populated and
    /// `force` is false, returns immediately so cycling Tab → ALL → Tab
    /// → ALL doesn't repeatedly hit the disk.
    ///
    /// File I/O runs on a `Task.detached` so the main actor stays free
    /// for the summon animation. The publish happens back on the main
    /// actor.
    public func loadApps(
        force: Bool = false,
        usageRecords: [UsageRecord] = [],
        runningBundleIDs: Set<String> = []
    ) {
        guard force || apps.isEmpty else {
            if !usageRecords.isEmpty || !runningBundleIDs.isEmpty {
                applyUsageOrdering(records: usageRecords, runningBundleIDs: runningBundleIDs)
            }
            return
        }
        isLoading = true
        // Reset transient view state on every reload so the user sees
        // the grid from a known origin.
        resetViewport()

        Task.detached(priority: .userInitiated) {
            let scanned = PerfSignpost.measure("GridState.scanInstalledApps") {
                Self.scanInstalledApps()
            }
            let ordered = Self.orderApps(
                scanned,
                usageRecords: usageRecords,
                runningBundleIDs: runningBundleIDs
            )
            // Warm the AppIconResolver NSCache for the first viewport so
            // SwiftUI's IconCell.task hits an in-memory image instead of
            // calling NSWorkspace.icon(forFile:) ~50× on the main actor
            // during the first ALL render.
            //
            // NSWorkspace.icon is documented main-thread-only on older
            // macOS — hop back so we don't hit an assert on macOS 12-13.
            // Top-80 covers ~7-9 cols × ~5-6 visible rows + a row of
            // scroll headroom on a typical 16" display.
            let prefetchTargets = ordered.prefix(80).map(\.bundleID)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.apps = ordered
                self.isLoading = false
                for bundleID in prefetchTargets {
                    AppIconResolver.prefetch(bundleID: bundleID)
                }
            }
        }
    }

    public func applyUsageOrdering(records: [UsageRecord], runningBundleIDs: Set<String> = []) {
        apps = Self.orderApps(apps, usageRecords: records, runningBundleIDs: runningBundleIDs)
    }

    /// Synchronous variant — used by tests + by `loadApps()` on the
    /// detached task. Pure file I/O, no actor isolation needed.
    nonisolated public static func scanInstalledApps() -> [GridApp] {
        let homeApps = FileManager.default
            .urls(for: .applicationDirectory, in: .userDomainMask)
            .first
        let searchPaths: [URL] = [
            URL(fileURLWithPath: "/Applications"),
            URL(fileURLWithPath: "/System/Applications"),
            homeApps,
        ].compactMap { $0 }

        var seen: Set<String> = []
        var out: [GridApp] = []

        for root in searchPaths {
            collect(in: root, depth: 0, seen: &seen, into: &out)
        }
        return out.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    nonisolated public static func orderApps(
        _ apps: [GridApp],
        usageRecords: [UsageRecord],
        runningBundleIDs: Set<String> = []
    ) -> [GridApp] {
        guard !apps.isEmpty else { return [] }
        var usageByID: [String: UsageRecord] = [:]
        for record in usageRecords {
            let id = record.app.bundleID
            if let existing = usageByID[id] {
                usageByID[id] = UsageRecord(
                    app: record.lastUsed >= existing.lastUsed ? record.app : existing.app,
                    activations: existing.activations + record.activations,
                    lastUsed: max(existing.lastUsed, record.lastUsed)
                )
            } else {
                usageByID[id] = record
            }
        }
        let now = Date()
        let scored = apps.map { app -> (GridApp, Double) in
            guard let usage = usageByID[app.bundleID] else { return (app, 0) }
            let ageHours = max(0, now.timeIntervalSince(usage.lastUsed) / 3600)
            let recency = 1 / (1 + ageHours / 24)
            let frequency = log(Double(usage.activations) + 1)
            let runningBonus = runningBundleIDs.contains(app.bundleID) ? 1.35 : 0
            return (app, recency * 3 + frequency + runningBonus)
        }
        let sorted = scored.sorted { lhs, rhs in
            if lhs.1 != rhs.1 { return lhs.1 > rhs.1 }
            return lhs.0.name.localizedCaseInsensitiveCompare(rhs.0.name) == .orderedAscending
        }
        return sorted.enumerated().map { rank, pair in
            GridApp(
                bundleID: pair.0.bundleID,
                name: pair.0.name,
                url: pair.0.url,
                rank: rank,
                usageScore: pair.1
            )
        }
    }

    /// Recursive walk: descend up to two levels deep so utility folders
    /// like `/Applications/Utilities` and `/System/Applications/Utilities`
    /// surface their contents. Bundles themselves are leaves — once we
    /// hit a `.app` we record it and stop descending into the bundle's
    /// internal `Contents/`.
    nonisolated private static func collect(
        in directory: URL,
        depth: Int,
        seen: inout Set<String>,
        into out: inout [GridApp]
    ) {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isApplicationKey],
            options: [.skipsHiddenFiles]
        )) ?? []
        for url in urls {
            if url.pathExtension == "app" {
                guard let bundle = Bundle(url: url),
                      let bid = bundle.bundleIdentifier,
                      !seen.contains(bid)
                else { continue }
                seen.insert(bid)
                let display: String = {
                    if let info = bundle.infoDictionary {
                        if let n = info["CFBundleDisplayName"] as? String, !n.isEmpty { return n }
                        if let n = info["CFBundleName"] as? String, !n.isEmpty { return n }
                    }
                    return (url.lastPathComponent as NSString).deletingPathExtension
                }()
                out.append(GridApp(bundleID: bid, name: display, url: url))
            } else if depth < 2 {
                let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
                if isDir {
                    collect(in: url, depth: depth + 1, seen: &seen, into: &out)
                }
            }
        }
    }

    /// Wheel notches retarget a velocity-preserving presentation spring.
    /// Trackpad pinch stays direct; both use the same 0.5–2.5 zoom bounds.
    public func applyWheelZoom(delta: CGFloat, in viewSize: CGSize) {
        viewportMotion.zoom(by: delta, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
    }

    public func beginViewportGesture() {
        viewportMotion.beginGesture()
        selectedBundleID = nil
    }

    public func endViewportGesture() { viewportMotion.stop() }

    public func coastViewport(by predictedTravel: CGSize, reduceMotion: Bool) {
        viewportMotion.coast(by: predictedTravel, reduceMotion: reduceMotion)
    }

    /// NSEvent already supplies trackpad momentum. Apply it one-to-one and
    /// cancel synthetic mouse/zoom motion rather than adding a second coast.
    public func panViewport(by delta: CGSize) {
        viewportMotion.stop()
        let next = HoneycombViewportGeometry.clamp(
            CGSize(width: panOffset.width + delta.width,
                   height: panOffset.height + delta.height), limits: viewportPanLimits)
        guard next != panOffset else { return }
        pointerSelectionSuppressed = true
        panOffset = next
    }

    /// Reset transient view state without touching the cached `apps`.
    /// Called when leaving grid mode so the next entry is fresh.
    public func resetViewport() {
        viewportMotion.stop()
        pointerSelectionSuppressed = false
        cellFrames = [:]
        panOffset = .zero
        zoomLevel = 1.0
        selectedBundleID = nil
        searchQuery = ""
        committingBundleID = nil
        draggingBundleID = nil
        dropTargetBundleID = nil
    }

    // MARK: - Keyboard selection helpers

    /// Find the visual neighbour for keyboard navigation. The grid is
    /// centre-out, not row-major, so arrows choose the nearest item in
    /// the requested spatial direction using the same honeycomb layout
    /// as the renderer. This keeps keyboard motion aligned with what
    /// the user sees after usage-ranked sorting.
    public func neighbourBundleID(
        of bundleID: String?,
        delta: Int,
        columns: Int
    ) -> String? {
        let list = filteredApps
        guard !list.isEmpty else { return nil }
        // No active selection → pick the first item the arrow would
        // logically land on (delta>0 from start, delta<0 from end).
        guard let current = bundleID,
              let idx = list.firstIndex(where: { $0.bundleID == current })
        else {
            return delta >= 0 ? list.first?.bundleID : list.last?.bundleID
        }
        let layout = HoneycombGeometry.spiralLayout(count: list.count)
        guard idx < layout.count else { return list[idx].bundleID }
        let currentPoint = HoneycombGeometry.center(
            row: layout[idx].row,
            col: layout[idx].col,
            spacing: 1
        )
        let axis: CGPoint = abs(delta) == 1
            ? CGPoint(x: delta > 0 ? 1 : -1, y: 0)
            : CGPoint(x: 0, y: delta > 0 ? 1 : -1)

        var best: (index: Int, score: CGFloat)?
        for candidateIndex in list.indices where candidateIndex != idx {
            let point = HoneycombGeometry.center(
                row: layout[candidateIndex].row,
                col: layout[candidateIndex].col,
                spacing: 1
            )
            let vx = point.x - currentPoint.x
            let vy = point.y - currentPoint.y
            let directional = vx * axis.x + vy * axis.y
            guard directional > 0.001 else { continue }
            let lateral = abs(vx * axis.y - vy * axis.x)
            let score = lateral * 3 + directional
            if best == nil || score < best!.score {
                best = (candidateIndex, score)
            }
        }
        return best.map { list[$0.index].bundleID } ?? list[idx].bundleID
    }

    /// Append a printable character to the search query. Caller is
    /// responsible for filtering control codes.
    public func appendSearch(_ ch: Character) {
        searchQuery.append(ch)
        // Selection might no longer match; let the view's onChange
        // re-seed it to the first filtered match.
        if let id = selectedBundleID,
           !filteredApps.contains(where: { $0.bundleID == id }) {
            selectedBundleID = filteredApps.first?.bundleID
        } else if selectedBundleID == nil {
            selectedBundleID = filteredApps.first?.bundleID
        }
    }

    /// Pop the last character from the search query; idempotent on empty.
    public func backspaceSearch() {
        guard !searchQuery.isEmpty else { return }
        searchQuery.removeLast()
        if let id = selectedBundleID,
           !filteredApps.contains(where: { $0.bundleID == id }) {
            selectedBundleID = filteredApps.first?.bundleID
        } else if selectedBundleID == nil {
            selectedBundleID = filteredApps.first?.bundleID
        }
    }

    /// Swap two apps in the in-memory catalogue. The order is not
    /// persisted yet; this gives the drag interaction a concrete,
    /// reversible macOS-grid behaviour without pretending folders are
    /// fully modelled.
    public func moveApp(bundleID: String, near targetBundleID: String, reduceMotion: Bool = false) {
        guard bundleID != targetBundleID,
              let from = apps.firstIndex(where: { $0.bundleID == bundleID }),
              let to = apps.firstIndex(where: { $0.bundleID == targetBundleID })
        else { return }
        withAnimation(.Halo.gridReflow(reduceMotion: reduceMotion)) {
            apps.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        }
        selectedBundleID = bundleID
    }
}
