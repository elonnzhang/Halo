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
            contentRect: NSRect(x: 0, y: 0, width: 720, height: 620),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Halo · Settings"
        w.contentViewController = host
        w.isReleasedWhenClosed = false
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

/// Sidebar + content split. macOS 12-compatible (no NavigationSplitView).
/// Mutations on `prefs` propagate via `objectWillChange`; the AppDelegate
/// sinks that and re-applies the snapshot to the running Halo.
struct SettingsRootView: View {
    @ObservedObject var prefs: AppPreferences
    @State private var selection: SettingsSection = .general

    var body: some View {
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
        case .about:     AboutTab()
        }
    }
}

// MARK: - Apps tab

// TODO: Apps 布局支持多 profile —— 现在只渲染单个 "Default" 绑定，
// 未来需要一个 profile 列表 + 切换器（"Default" / "Work" / "Gaming"...），
// 每个 profile 独立维护 pinnedBundleIDs / identityOverride。AppPreferences
// 已留了 `clearAllBindings()` 入口，以后按 profile 维度切桶即可。
struct AppsTab: View {
    @ObservedObject var prefs: AppPreferences

    @State private var confirmingClear = false

    var body: some View {
        Form {
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
                    Text("Default binding")
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

// MARK: - Whitelist tab placeholder

/// Real implementation lives in `WhitelistTab.swift` (Phase 5). Kept here
/// only because `SettingsRootView` routes to it; Phase 5 deletes this stub.
struct WhitelistTab: View {
    @ObservedObject var prefs: AppPreferences
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "shield")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("Whitelist UI lands in Phase 5")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
