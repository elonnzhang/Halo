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
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Centre after the window is on screen so SwiftUI has had a
        // run-loop tick to finalise NSHostingController's intrinsic
        // content size; otherwise `window.frame.size` still reflects
        // the init `contentRect` (880 × 720 + titlebar) and the
        // post-layout shrink/grow would offset the window from centre.
        DispatchQueue.main.async { [weak self] in
            self?.centerOnCurrentScreen()
        }
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
            // `MainActor.assumeIsolated` is macOS 14+ only; hop via
            // `Task { @MainActor in ... }` so the close handler stays safe
            // on macOS 12 / 13 while preserving strict-concurrency
            // isolation (mirrors AppDelegate's global event monitor).
            Task { @MainActor in
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

            // Per-profile knobs. v1.3.0 lifts slot count, ambient tint,
            // and ranking strategy onto the active profile — General
            // tab no longer carries any of these. Switching profile
            // from the bar above re-binds every control in this
            // section to the new active profile's value.
            Section {
                Picker("Slot count", selection: Binding(
                    get: { prefs.slotCount },
                    set: { prefs.slotCount = $0 }
                )) {
                    ForEach([4, 6, 8, 10, 12], id: \.self) { Text("\($0)").tag($0) }
                }
                .pickerStyle(.segmented)

                tintPicker

                Picker("Ranking", selection: Binding(
                    get: { prefs.frequencyProfile },
                    set: { prefs.frequencyProfile = $0 }
                )) {
                    Text("MFU").tag(FrequencyProfile.mfuOnly)
                    Text("Balanced").tag(FrequencyProfile.balanced)
                    Text("MRU").tag(FrequencyProfile.mruOnly)
                }
                .pickerStyle(.segmented)
            } header: {
                Text(String(format: NSLocalizedString("Profile settings for %@", comment: ""),
                            prefs.activeProfile.name))
            } footer: {
                Text("Each profile remembers its own slot count, tint, and ranking. Tab / ⇧Tab during summon switches profiles.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

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

    // MARK: - Tint picker

    /// Eight OKLCH-tuned swatches + a "no tint" cell. Selecting a
    /// swatch writes it as the active profile's ambient `tint`; the "no
    /// tint" cell clears it. Selection is ring-outlined; matching is by
    /// hue within a small tolerance so the picker stays visually stable
    /// even if a swatch was previously round-tripped through sRGB.
    private var tintPicker: some View {
        // Manual HStack instead of `LabeledContent` because the latter
        // is macOS 13+. SwiftUI Form already gives the row a uniform
        // baseline, so a plain `Text("Tint") ... Spacer() ... swatches`
        // layout reads the same.
        HStack(spacing: 6) {
            Text("Tint")
            Spacer()
            ForEach(Array(Self.tintSwatches.enumerated()), id: \.offset) { _, swatch in
                swatchButton(swatch)
            }
            Button {
                prefs.setTint(nil, for: prefs.activeProfileID)
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.30), lineWidth: 1)
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 18, height: 18)
                .overlay(selectionRing(isSelected: prefs.activeProfile.tint == nil))
            }
            .buttonStyle(.plain)
            .help("No tint")
        }
    }

    private func swatchButton(_ color: IdentityColor) -> some View {
        let selected = matchesActiveTint(color)
        return Button {
            prefs.setTint(color, for: prefs.activeProfileID)
        } label: {
            Circle()
                .fill(color.swiftUIColor)
                .frame(width: 18, height: 18)
                .overlay(selectionRing(isSelected: selected))
        }
        .buttonStyle(.plain)
    }

    private func selectionRing(isSelected: Bool) -> some View {
        Circle()
            .strokeBorder(
                isSelected ? Color.accentColor : Color.clear,
                lineWidth: 2
            )
            .padding(-3)
    }

    private func matchesActiveTint(_ color: IdentityColor) -> Bool {
        guard let active = prefs.activeProfile.tint else { return false }
        return abs(active.lightness - color.lightness) < 0.01
            && abs(active.chroma - color.chroma) < 0.01
            && IdentityColor.hueDistance(active.hue, color.hue) < 1.0
    }

    /// Eight swatches at perceptually-matched lightness/chroma, sweeping
    /// hue. Wide enough to give the user a recognisable "scene colour"
    /// without offering the full OKLCH gamut here (the wheel's per-app
    /// override popover is where finer control lives).
    private static let tintSwatches: [IdentityColor] = [
        IdentityColor(lightness: 0.65, chroma: 0.18, hue: 25),   // red
        IdentityColor(lightness: 0.72, chroma: 0.17, hue: 55),   // orange
        IdentityColor(lightness: 0.78, chroma: 0.16, hue: 90),   // amber
        IdentityColor(lightness: 0.72, chroma: 0.17, hue: 140),  // green
        IdentityColor(lightness: 0.68, chroma: 0.14, hue: 190),  // teal
        IdentityColor(lightness: 0.62, chroma: 0.18, hue: 230),  // blue
        IdentityColor(lightness: 0.60, chroma: 0.20, hue: 285),  // violet
        IdentityColor(lightness: 0.65, chroma: 0.18, hue: 325),  // magenta
    ]

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
/// Settings → Apps empty-slot picker. Thin host around the shared
/// `AppListPicker`; keeps its `onPick` contract so `BindingWheelView`'s
/// `.sheet { AppPickerSheet { … } }` is unchanged.
struct AppPickerSheet: View {
    let onPick: (String?) -> Void

    var body: some View {
        AppListPicker(onPick: onPick)
            .frame(width: 480, height: 460)
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
