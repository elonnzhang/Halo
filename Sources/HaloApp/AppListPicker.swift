import AppKit
import SwiftUI
import HaloUI

/// Off-main loader for the installed-app catalogue behind `AppListPicker`.
///
/// Mirrors `GridState.loadApps`: scans on a detached task, publishes on the
/// main actor, and warms `AppIconResolver`'s cache for the first viewport so
/// opening the picker never blocks on file I/O or icon decode. Kept a small
/// `@MainActor` class (rather than inline `Task` in the View) so the detached
/// closure captures `[weak self]` on a Sendable reference instead of the
/// picker struct, which stores a non-Sendable `onPick` closure.
@MainActor
private final class AppCatalogLoader: ObservableObject {
    @Published var apps: [GridState.GridApp] = []
    @Published var runningBundleIDs: Set<String> = []
    @Published var isLoading = true

    func load() {
        guard isLoading else { return }   // one scan per picker instance
        Task.detached(priority: .userInitiated) { [weak self] in
            // Reuse the ALL grid's scanner: /Applications, /System/Applications,
            // ~/Applications with depth-2 recursion (Utilities surface), deduped
            // by bundleID, alphabetically sorted — coverage parity for free.
            let scanned = GridState.scanInstalledApps()
            let prefetch = scanned.prefix(80).map(\.bundleID)
            await MainActor.run {
                guard let self else { return }
                self.apps = scanned
                self.runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
                self.isLoading = false
                // Warm the icon cache so the first visible rows hit memory
                // instead of NSWorkspace.icon on the main thread.
                for id in prefetch { AppIconResolver.prefetch(bundleID: id) }
            }
        }
    }
}

/// Shared Finder-style app picker used by both the Settings → Apps sheet
/// (`AppPickerSheet`) and the live empty-slot window (`PinPickerView`).
///
/// Finder-minimal rows — app icon + name, no bundleID. Alphabetical order.
/// A custom top search field (rather than `.searchable`) so the same view
/// behaves identically inside a sheet and a bare `NSWindow` without a
/// navigation container. Hosted inside a fixed-size frame by each caller.
struct AppListPicker: View {
    let onPick: (String?) -> Void

    @StateObject private var loader = AppCatalogLoader()
    @State private var search = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            searchRow
            Divider()
            content
        }
        .onAppear {
            loader.load()
            searchFocused = true
        }
    }

    @ViewBuilder
    private var content: some View {
        if loader.isLoading {
            ProgressView()
                .controlSize(.small)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let running = filtered.filter { loader.runningBundleIDs.contains($0.bundleID) }
            let installed = filtered.filter { !loader.runningBundleIDs.contains($0.bundleID) }
            if filtered.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 24, weight: .light))
                        .foregroundStyle(.secondary)
                    Text(NSLocalizedString("No matching apps", comment: "App picker empty state"))
                        .font(.headline)
                    Text(NSLocalizedString("Try a different name or bundle ID.", comment: "App picker empty state"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 18) {
                        if !running.isEmpty {
                            appSection(
                                title: NSLocalizedString("Running now", comment: "App picker section"),
                                apps: running,
                                isRunning: true
                            )
                        }
                        if !installed.isEmpty {
                            appSection(
                                title: NSLocalizedString("All applications", comment: "App picker section"),
                                apps: installed,
                                isRunning: false
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
            }
        }
    }

    private func appSection(title: String, apps: [GridState.GridApp], isRunning: Bool) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(apps.count)")
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 82, maximum: 112), spacing: 10)],
                spacing: 10
            ) {
                ForEach(apps, id: \.bundleID) { app in
                    Button { onPick(app.bundleID) } label: {
                        AppGridTile(bundleID: app.bundleID, name: app.name, isRunning: isRunning)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search apps", text: $search)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                // Return commits the first filtered match — fast keyboard pin.
                .onSubmit { if let first = displayedApps.first { onPick(first.bundleID) } }
            if !search.isEmpty {
                Button {
                    search = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            Button("Cancel") { onPick(nil) }
        }
        .padding(12)
    }

    private var filtered: [GridState.GridApp] {
        guard !search.isEmpty else { return loader.apps }
        let q = search.lowercased()
        return loader.apps.filter {
            $0.name.lowercased().contains(q) || $0.bundleID.lowercased().contains(q)
        }
    }

    /// Mirrors the visual order: running applications are promoted above
    /// the full installed catalogue so Return always chooses the first row
    /// the user is looking at.
    private var displayedApps: [GridState.GridApp] {
        filtered.filter { loader.runningBundleIDs.contains($0.bundleID) }
            + filtered.filter { !loader.runningBundleIDs.contains($0.bundleID) }
    }
}

/// One Finder-minimal tile: app icon + name. The icon loads through the shared
/// `AppIconResolver` cache via `.task(id:)` — the same pattern the ALL grid's
/// `IconCell` uses, so a recycled tile re-fetches when its bundleID changes.
private struct AppGridTile: View {
    let bundleID: String
    let name: String
    let isRunning: Bool
    @State private var icon: NSImage?

    var body: some View {
        VStack(spacing: 7) {
            Group {
                if let icon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                } else {
                    RoundedRectangle(cornerRadius: 13, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .bottomTrailing) {
                if isRunning {
                    Circle()
                        .fill(Color.green)
                        .frame(width: 10, height: 10)
                        .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
                        .accessibilityHidden(true)
                }
            }
            Text(name)
                .font(.system(size: 11.5, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .top)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 5)
        .frame(maxWidth: .infinity, minHeight: 101)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.primary.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.6)
        )
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .accessibilityLabel(Text(isRunning ? "\(name), \(NSLocalizedString("Running", comment: "App picker status"))" : name))
        .task(id: bundleID) {
            icon = AppIconResolver.icon(for: bundleID)
        }
    }
}
