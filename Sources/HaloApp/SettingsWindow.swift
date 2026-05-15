import AppKit
import SwiftUI
import HaloCore
import HaloUI

// MARK: - NSWindow controller

/// Hosts `SettingsRootView` inside a `NSHostingController` and manages the
/// activation-policy dance: bumps Halo to `.regular` so the Settings window
/// promotes to the foreground, then reverts to `.accessory` (menu-bar only)
/// when the window closes.
@MainActor
final class SettingsWindowController {
    private let window: NSWindow
    private let prefs: AppPreferences

    init(prefs: AppPreferences) {
        self.prefs = prefs
        let host = NSHostingController(rootView: SettingsRootView(prefs: prefs))
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 880, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        w.title = "Halo · Settings"
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.contentViewController = host
        w.isReleasedWhenClosed = false
        // Let SwiftUI's NavigationSplitView own the min size — its
        // `.frame(minWidth: 760, minHeight: 600)` is the source of truth.
        w.contentMinSize = NSSize(width: 760, height: 600)
        self.window = w
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        centerOnCurrentScreen()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        WindowCloseObserver.attach(window: window) {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    /// Focus the Actions tab and pre-select `bundleID`. Used by AppDelegate
    /// when the user commits an empty action slot — opens Settings already
    /// scrolled to the right app so they can configure on the spot.
    func focusActionsTab(bundleID: String) {
        SettingsFocusCoordinator.shared.requestFocus(.actions, bundleID: bundleID)
    }

    /// Centres on the screen the cursor is currently on, not on `NSScreen.main`.
    /// On multi-display setups the user expects Settings to land where they're
    /// looking — usually the same display as the menu-bar item they just
    /// clicked — rather than always on the primary display.
    private func centerOnCurrentScreen() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = window.frame.size
        window.setFrameOrigin(NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.midY - size.height / 2
        ))
    }
}

/// Watches an NSWindow for its close notification so we can flip activation
/// policy back to `.accessory` without subclassing the window.
@MainActor
private final class WindowCloseObserver {
    static var observers: [ObjectIdentifier: WindowCloseObserver] = [:]
    let token: NSObjectProtocol
    let handler: () -> Void

    static func attach(window: NSWindow, handler: @escaping () -> Void) {
        let observer = WindowCloseObserver(window: window, handler: handler)
        observers[ObjectIdentifier(window)] = observer
    }

    private init(window: NSWindow, handler: @escaping () -> Void) {
        self.handler = handler
        let id = ObjectIdentifier(window)
        self.token = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                let observer = Self.observers[id]
                observer?.handler()
                Self.observers.removeValue(forKey: id)
            }
        }
    }
}

// MARK: - SwiftUI root

/// Sidebar + content split. On macOS 13+ uses the native
/// `NavigationSplitView` so the panel inherits the system Settings look —
/// translucent sidebar, accent-tinted selection pill, collapsible chrome,
/// Liquid Glass on macOS 26. macOS 12 falls back to a hand-built `HStack`.
struct SettingsRootView: View {
    @ObservedObject var prefs: AppPreferences
    @StateObject private var focus = SettingsFocusCoordinator.shared
    @State private var selection: SettingsSection = .general
    /// BundleID forwarded from `AppDelegate.openActionEditor` when the
    /// user commits an empty action slot. Cleared once consumed by
    /// `ActionsTab`.
    @State private var pendingActionsBundleID: String?

    var body: some View {
        Group {
            if #available(macOS 13.0, *) {
                nativeSplit
            } else {
                legacySplit
            }
        }
        .onAppear { applyPendingFocus() }
        .onChange(of: focus.tick) { _ in applyPendingFocus() }
    }

    private func applyPendingFocus() {
        if let section = focus.pendingSection {
            selection = section
            focus.pendingSection = nil
        }
        if let bid = focus.pendingActionsBundleID {
            pendingActionsBundleID = bid
            focus.pendingActionsBundleID = nil
        }
    }

    @available(macOS 13.0, *)
    @ViewBuilder
    private var nativeSplit: some View {
        NavigationSplitView {
            List(SettingsSection.allCases, selection: $selection) { section in
                Label {
                    Text(section.localizedTitle)
                } icon: {
                    Image(systemName: section.systemImage)
                        .foregroundStyle(.tint)
                }
                .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            content
                .frame(minWidth: 560)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 760, idealWidth: 880, minHeight: 600, idealHeight: 720)
    }

    @ViewBuilder
    private var legacySplit: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selection)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 720, height: 620)
    }

    @ViewBuilder
    private var content: some View {
        switch selection {
        case .general:   GeneralTab(prefs: prefs)
        case .apps:      AppsTab(prefs: prefs)
        case .whitelist: WhitelistTab(prefs: prefs)
        case .actions:   ActionsTab(prefs: prefs, focusBundleID: $pendingActionsBundleID)
        case .about:     AboutTab()
        }
    }
}

/// Cross-component pipe so `AppDelegate.openActionEditor` can request the
/// Settings window switch to a specific tab + pre-select a bundleID
/// without us having to refactor SettingsRootView's state ownership.
/// The tick counter exists because SwiftUI's `onChange` doesn't fire on
/// repeated identical values — we want a re-trigger if the user commits
/// the same empty slot twice in a row.
@MainActor
final class SettingsFocusCoordinator: ObservableObject {
    static let shared = SettingsFocusCoordinator()
    @Published var pendingSection: SettingsSection?
    @Published var pendingActionsBundleID: String?
    @Published var tick: Int = 0
    private init() {}

    func requestFocus(_ section: SettingsSection, bundleID: String? = nil) {
        pendingSection = section
        pendingActionsBundleID = bundleID
        tick &+= 1
    }
}

// MARK: - Apps tab

struct AppsTab: View {
    @ObservedObject var prefs: AppPreferences

    @State private var confirmingClear = false

    var body: some View {
        Form {
            Section {
                ProfileBar(prefs: prefs)
            }

            bindingHeader

            Section {
                BindingWheelView(prefs: prefs)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            } header: {
                Text("Tap a slot to pin an app or manage its identity colour. Empty slots are filled by frequency at summon time.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            if !prefs.overflowPinnedBundleIDs.isEmpty {
                Section("Hidden pins (slot count too low)") {
                    ForEach(prefs.overflowPinnedBundleIDs, id: \.self) { id in
                        HStack {
                            if let icon = AppIconResolver.icon(for: id) {
                                Image(nsImage: icon).resizable().frame(width: 18, height: 18)
                            }
                            Text(displayName(for: id))
                            Spacer()
                            Text(id)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .compatGroupedFormStyle()
        .alert("Clear all pinned apps?", isPresented: $confirmingClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                prefs.clearAllBindings()
            }
        } message: {
            Text("All slot pins and identity-colour overrides will be reset. This cannot be undone.")
        }
    }

    /// "Halo binding" card at the top of the Apps tab.
    private var bindingHeader: some View {
        Section {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.18))
                    Image(systemName: "circle.dashed.inset.filled")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text(prefs.activeProfile.name)
                        .font(.headline)
                    Text(bindingSummary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("Clear all", role: .destructive) {
                    confirmingClear = true
                }
                .controlSize(.regular)
            }
            .padding(.vertical, 4)
        }
    }

    private var bindingSummary: String {
        let pinned = prefs.pinnedBundleIDs.compactMap { $0 }.count
        let slots = prefs.slotCount
        return String(
            format: NSLocalizedString("%d pinned · %d slots", comment: "Apps tab binding summary"),
            pinned,
            slots
        )
    }

    private func displayName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return bundleID }
        return (url.lastPathComponent as NSString).deletingPathExtension
    }
}

// MARK: - App picker sheet

// Internal visibility (no `private`) so `BindingWheelView` in a sibling
// file can host this sheet for the per-slot Pin… action.
struct AppPickerSheet: View {
    let onPick: (String?) -> Void
    @State private var apps: [(bundleID: String, name: String, url: URL)] = []
    @State private var search = ""

    var body: some View {
        CompatNavigationContainer {
            List(filtered, id: \.bundleID) { item in
                Button {
                    onPick(item.bundleID)
                } label: {
                    HStack {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                            .resizable().frame(width: 20, height: 20)
                        Text(item.name)
                        Spacer()
                        Text(item.bundleID).font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                }
                .buttonStyle(.plain)
            }
            .searchable(text: $search, placement: .toolbar, prompt: "Search apps")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { onPick(nil) }
                }
            }
        }
        .frame(width: 480, height: 460)
        .onAppear(perform: load)
    }

    private var filtered: [(bundleID: String, name: String, url: URL)] {
        guard !search.isEmpty else { return apps }
        let q = search.lowercased()
        return apps.filter { $0.name.lowercased().contains(q) || $0.bundleID.lowercased().contains(q) }
    }

    private func load() {
        var seen: Set<String> = []
        var out: [(String, String, URL)] = []
        let searchPaths = ["/Applications", "/System/Applications"]
        for path in searchPaths {
            let urls = (try? FileManager.default.contentsOfDirectory(
                at: URL(fileURLWithPath: path),
                includingPropertiesForKeys: [.isApplicationKey],
                options: [.skipsHiddenFiles]
            )) ?? []
            for url in urls where url.pathExtension == "app" {
                guard let bundle = Bundle(url: url),
                      let bid = bundle.bundleIdentifier,
                      !seen.contains(bid)
                else { continue }
                seen.insert(bid)
                let name = (url.lastPathComponent as NSString).deletingPathExtension
                out.append((bid, name, url))
            }
        }
        apps = out.sorted { $0.1.lowercased() < $1.1.lowercased() }
            .map { (bundleID: $0.0, name: $0.1, url: $0.2) }
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
