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
            contentRect: NSRect(x: 0, y: 0, width: 960, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Halo Settings"
        w.titleVisibility = .visible
        w.titlebarAppearsTransparent = false
        w.contentViewController = host
        w.isReleasedWhenClosed = false
        // Let SwiftUI's NavigationSplitView own the min size — its
        // `.frame(minWidth: 760, minHeight: 600)` is the source of truth.
        w.contentMinSize = NSSize(width: 900, height: 640)
        // SwiftUI may report an unconstrained intrinsic size after the
        // NavigationSplitView lays out. Keep the utility window compact and
        // predictable instead of letting the first render stretch it toward
        // the screen edge.
        w.setContentSize(NSSize(width: 960, height: 760))
        w.isRestorable = false
        self.window = w
    }

    func show() {
        NSApp.setActivationPolicy(.regular)
        // Reapply the intended content size on every presentation. This also
        // corrects a frame that was previously dragged or expanded before
        // the next open.
        window.setContentSize(NSSize(width: 960, height: 760))
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        // Centre after the window is on screen so SwiftUI has had a
        // run-loop tick to finalise NSHostingController's intrinsic
        // content size; otherwise `window.frame.size` still reflects
        // the init `contentRect` (880 × 720 + titlebar) and the
        // post-layout shrink/grow would offset the window from centre.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window.setContentSize(NSSize(width: 960, height: 760))
            self.centerOnCurrentScreen()
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
        // A standalone utility window should own its split layout. Using
        // NavigationSplitView here adds a toolbar/sidebar toggle and can
        // place detail content under the titlebar on macOS, which creates
        // the clipped header and the large blank band seen in Settings.
        legacySplit
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
            List(selection: $selection) {
                Section {
                    ForEach([SettingsSection.general, .apps, .whitelist, .actions]) { section in
                        sidebarRow(section)
                    }
                }
                Section {
                    sidebarRow(.about)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            content
                .frame(minWidth: 680, maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 900, idealWidth: 960, minHeight: 640, idealHeight: 760)
    }

    @ViewBuilder
    private var legacySplit: some View {
        HStack(spacing: 0) {
            // Fixed, non-collapsing sidebar. `SettingsSidebar` is a rigid
            // 200pt column; pinning it with a matching frame + layoutPriority
            // stops SwiftUI from squeezing it when the detail pane wants more
            // room, so the nav labels never truncate ("用" / "名单" clipping).
            SettingsSidebar(selection: $selection)
                .frame(width: 200)
                .layoutPriority(1)
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // Min width fits the fixed 200pt sidebar + the Apps hero at its
        // natural size (controls column + 280pt wheel + paddings) so the
        // scene card never clips regardless of how the user resizes.
        .frame(minWidth: 900, idealWidth: 960, minHeight: 640, idealHeight: 760)
    }

    @available(macOS 13.0, *)
    @ViewBuilder
    private func sidebarRow(_ section: SettingsSection) -> some View {
        Label {
            Text(section.localizedTitle)
        } icon: {
            Image(systemName: section.systemImage)
                .foregroundStyle(.tint)
        }
        .tag(section)
        .accessibilityHint(Text(section.subtitle))
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sceneChipRow
                heroCard
                if !prefs.overflowPinnedBundleIDs.isEmpty {
                    hiddenPinsCard
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert("Clear all pinned apps?", isPresented: $confirmingClear) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                prefs.clearAllBindings()
            }
        } message: {
            Text("All slot pins and identity-colour overrides will be reset. This cannot be undone.")
        }
    }

    // MARK: - Scene chip row

    /// Top strip: the scene switcher. `ProfileBar` renders the pills, the
    /// left-aligned "Show ALL" tab, and the trailing count — Show ALL lives
    /// there (not on the panel's trailing edge) so it stays beside the pills
    /// as the window narrows.
    private var sceneChipRow: some View {
        ProfileBar(prefs: prefs)
    }

    // MARK: - Hero card (Design C)

    /// The active profile presented as a single tinted hero: controls on
    /// the left, the live wheel on the right. The card background is a soft
    /// wash of the profile's ambient tint, so changing the scene or its
    /// colour recolours the whole preview — the switcher above and the
    /// knobs here read as one unit instead of stacked, disconnected rows.
    private var heroCard: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 22) {
                heroControls
                    .frame(maxWidth: .infinity, alignment: .leading)
                heroWheel
            }
            .padding(22)

            Text("Tap a slot on the wheel to pin an app or adjust its identity colour. Empty slots are filled by frequency at summon time.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 22)
                .padding(.bottom, 18)
        }
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        gradient: Gradient(colors: [
                            profileColor.opacity(0.12),
                            Color(NSColor.windowBackgroundColor).opacity(0.0),
                        ]),
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(NSColor.windowBackgroundColor).opacity(0.5))
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(profileColor.opacity(0.22), lineWidth: 1)
        )
    }

    /// Left column of the hero: scene identity + the three per-profile
    /// knobs, each under its own uppercase caption.
    private var heroControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 10) {
                ZStack {
                    Circle().fill(profileColor.opacity(0.18))
                    Image(systemName: "circle.dashed.inset.filled")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundStyle(profileColor)
                }
                .frame(width: 34, height: 34)
                VStack(alignment: .leading, spacing: 1) {
                    Text(prefs.activeProfile.name)
                        .font(.system(size: 19, weight: .bold))
                    Text(bindingSummary)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            controlGroup("Slot count") {
                Picker("", selection: Binding(
                    get: { prefs.slotCount },
                    set: { prefs.slotCount = $0 }
                )) {
                    ForEach([4, 6, 8, 10, 12], id: \.self) { Text("\($0)").tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }

            controlGroup("Tint") {
                tintSwatchRow
            }

            controlGroup("Ranking") {
                Picker("", selection: Binding(
                    get: { prefs.frequencyProfile },
                    set: { prefs.frequencyProfile = $0 }
                )) {
                    Text("MFU").tag(FrequencyProfile.mfuOnly)
                    Text("Balanced").tag(FrequencyProfile.balanced)
                    Text("MRU").tag(FrequencyProfile.mruOnly)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .fixedSize()
            }
        }
    }

    /// Right column of the hero: the live binding wheel + a destructive
    /// "Clear all" beneath it.
    private var heroWheel: some View {
        VStack(spacing: 12) {
            BindingWheelView(prefs: prefs)
            Button("Clear all", role: .destructive) {
                confirmingClear = true
            }
            .controlSize(.regular)
        }
    }

    /// A labelled control block used across the hero's left column: an
    /// uppercase caption stacked over its control.
    @ViewBuilder
    private func controlGroup<Content: View>(
        _ titleKey: LocalizedStringKey,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(titleKey)
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            content()
        }
    }

    /// Hidden-pin overflow, shown as its own card below the hero when the
    /// slot count is too low to surface every pin.
    private var hiddenPinsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Hidden pins (slot count too low)")
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
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
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }

    /// The active profile's ambient tint, or the accent colour when none is
    /// set — mirrors the pill-dot logic in `ProfileBar` so the card and the
    /// selected pill share one colour.
    private var profileColor: Color {
        prefs.activeProfile.tint?.swiftUIColor ?? Color.accentColor
    }

    // MARK: - Tint picker

    /// Eight OKLCH-tuned swatches + a "no tint" cell. Selecting a
    /// swatch writes it as the active profile's ambient `tint`; the "no
    /// tint" cell clears it. Selection is ring-outlined; matching is by
    /// hue within a small tolerance so the picker stays visually stable
    /// even if a swatch was previously round-tripped through sRGB.
    private var tintSwatchRow: some View {
        // Swatches only — the enclosing controlGroup supplies the "Tint"
        // caption, so this row is left-aligned with no leading label.
        HStack(spacing: 8) {
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
            .frame(width: 560, height: 560)
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
