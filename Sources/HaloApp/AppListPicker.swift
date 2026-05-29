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
            List(filtered, id: \.bundleID) { app in
                Button {
                    onPick(app.bundleID)
                } label: {
                    AppListRow(bundleID: app.bundleID, name: app.name)
                }
                .buttonStyle(.plain)
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
                .onSubmit { if let first = filtered.first { onPick(first.bundleID) } }
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
}

/// One Finder-minimal row: app icon + name. The icon loads through the shared
/// `AppIconResolver` cache via `.task(id:)` — the same pattern the ALL grid's
/// `IconCell` uses, so a recycled row re-fetches when its bundleID changes.
private struct AppListRow: View {
    let bundleID: String
    let name: String
    @State private var icon: NSImage?

    var body: some View {
        HStack(spacing: 8) {
            Group {
                if let icon {
                    Image(nsImage: icon).resizable()
                } else {
                    Color.clear
                }
            }
            .frame(width: 20, height: 20)
            Text(name)
            Spacer()
        }
        .contentShape(Rectangle())
        .task(id: bundleID) {
            icon = AppIconResolver.icon(for: bundleID)
        }
    }
}
