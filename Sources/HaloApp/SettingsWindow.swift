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
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 540),
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

/// Settings UI hosted inside `SettingsWindowController`. Four tabs:
/// General, Hotkey, Apps (merged Pins + Colors), About.
///
/// Mutations on `prefs` propagate automatically — `AppDelegate.prefsObserver`
/// sinks `objectWillChange` and re-applies the snapshot to the running Halo —
/// so no `onChange` callback is threaded through.
struct SettingsRootView: View {
    @ObservedObject var prefs: AppPreferences

    var body: some View {
        TabView {
            GeneralTab(prefs: prefs)
                .tabItem { Label("General", systemImage: "gearshape") }
            HotkeyTab(prefs: prefs)
                .tabItem { Label("Hotkey", systemImage: "command") }
            AppsTab(prefs: prefs)
                .tabItem { Label("Apps", systemImage: "square.grid.3x3.fill") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(16)
        .frame(width: 560, height: 540)
    }
}

// MARK: - General

private struct GeneralTab: View {
    @ObservedObject var prefs: AppPreferences

    /// Generic layout-slider row: label on the left, slider in the
    /// middle, current value (with unit) on the right. Used by the
    /// "Wheel layout" section for Halo diameter / icon size / icon
    /// distance.
    @ViewBuilder
    private func layoutSlider(
        label: LocalizedStringKey,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        suffix: String
    ) -> some View {
        HStack(spacing: 12) {
            Text(label)
                .frame(width: 110, alignment: .leading)
            Slider(value: value, in: range, step: step)
            Text("\(Int(value.wrappedValue)) \(suffix)")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
        }
    }

    /// Pulls the last hour of unified-log entries under the Halo
    /// subsystem into `~/Downloads/Halo-diagnostic-<timestamp>.log` and
    /// reveals it in Finder. Bound to the Settings button; surfaces any
    /// error via an `NSAlert` so the user knows what to attach to a bug
    /// report instead of getting a silent failure.
    private func exportDiagnostics() {
        do {
            let url = try DiagnosticLog.export()
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            let alert = NSAlert()
            alert.messageText = NSLocalizedString(
                "Could not export diagnostic log",
                comment: "Alert title shown when log export fails"
            )
            alert.informativeText = error.localizedDescription
            alert.alertStyle = .warning
            alert.addButton(withTitle: NSLocalizedString("OK", comment: ""))
            alert.runModal()
        }
    }

    var body: some View {
        Form {
            Section("Layout") {
                Picker("Slot count", selection: Binding(
                    get: { prefs.slotCount },
                    set: { prefs.slotCount = $0 }
                )) {
                    ForEach([4, 6, 8, 10, 12], id: \.self) { n in
                        Text("\(n)").tag(n)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Summon position", selection: Binding(
                    get: { prefs.summonPosition },
                    set: { prefs.summonPosition = $0 }
                )) {
                    Text("At cursor").tag(SummonPosition.mouse)
                    Text("Screen center").tag(SummonPosition.center)
                }
                .pickerStyle(.segmented)
            }

            Section("Ranking") {
                Picker("Frequency profile", selection: Binding(
                    get: { prefs.frequencyProfile },
                    set: { prefs.frequencyProfile = $0 }
                )) {
                    Text("MFU only").tag(FrequencyProfile.mfuOnly)
                    Text("Balanced").tag(FrequencyProfile.balanced)
                    Text("MRU only").tag(FrequencyProfile.mruOnly)
                }
                .pickerStyle(.segmented)
            }

            Section {
                layoutSlider(
                    label: "Halo diameter",
                    value: Binding(
                        get: { Double(prefs.haloDiameter) },
                        set: { prefs.haloDiameter = CGFloat($0) }
                    ),
                    range: 280...440,
                    step: 10,
                    suffix: "pt"
                )
                layoutSlider(
                    label: "Icon size",
                    value: Binding(
                        get: { Double(prefs.iconSize) },
                        set: { prefs.iconSize = CGFloat($0) }
                    ),
                    range: 36...64,
                    step: 2,
                    suffix: "pt"
                )
                let radiusBounds = prefs.iconRadiusBounds
                layoutSlider(
                    label: "Icon distance",
                    value: Binding(
                        get: { Double(prefs.iconRadius) },
                        set: { prefs.iconRadius = CGFloat($0) }
                    ),
                    range: Double(radiusBounds.min)...Double(radiusBounds.max),
                    step: 2,
                    suffix: "pt"
                )
                Button("Reset wheel layout") {
                    prefs.resetLayout()
                }
            } header: {
                Text("Wheel layout")
            } footer: {
                Text("Summon Halo to see size changes take effect.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Section("Startup") {
                Toggle("Launch Halo at login", isOn: Binding(
                    get: { prefs.autostart },
                    set: { prefs.autostart = $0; LaunchAgentManager.apply(enabled: $0) }
                ))

                Button("Replay welcome guide") {
                    (NSApp.delegate as? AppDelegate)?.replayWelcome()
                }
                Button("Reset onboarding overlay") {
                    prefs.resetOnboarding()
                }
                Button("Export diagnostic log…") {
                    exportDiagnostics()
                }
            }

            Section {
                Picker("Display language", selection: Binding(
                    get: { prefs.appLanguageOverride ?? "system" },
                    set: { prefs.appLanguageOverride = ($0 == "system" ? nil : $0) }
                )) {
                    Text("System").tag("system")
                    Text("English").tag("en")
                    Text("简体中文").tag("zh-Hans")
                }
                .pickerStyle(.menu)
            } header: {
                Text("Language")
            } footer: {
                Text("Restart Halo for the language change to take effect.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .compatGroupedFormStyle()
    }
}

// MARK: - Hotkey

private struct HotkeyTab: View {
    @ObservedObject var prefs: AppPreferences
    @State private var capturing = false

    var body: some View {
        Form {
            Section {
                HStack {
                    Text("Summon hotkey")
                    Spacer()
                    Text("\(prefs.hotkeyModifiers.symbols)\(KeyName.label(for: prefs.hotkeyKeyCode))")
                        .font(.system(.body, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .modifier(KeyCapChip(active: capturing))
                    Button(capturing ? "Press chord…" : "Rebind") {
                        capturing.toggle()
                    }
                }
                if capturing {
                    HotkeyCaptureView(prefs: prefs) {
                        capturing = false
                    }
                }
                Button("Reset to ⌘ ⌥ Space") {
                    prefs.hotkeyKeyCode = 49
                    prefs.hotkeyModifiers = [.command, .option]
                }
            } header: {
                Text("Press the hotkey to summon instantly; release to commit the highlighted slot.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }

            Section {
                HStack {
                    Text("Double-tap ⌘ window")
                    Slider(
                        value: Binding(
                            get: { prefs.cmdDoubleTapGap },
                            set: { prefs.cmdDoubleTapGap = $0 }
                        ),
                        in: 0.15...0.50,
                        step: 0.05
                    )
                    Text(String(format: "%.2f s", prefs.cmdDoubleTapGap))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 56, alignment: .trailing)
                }
            } header: {
                Text("Second trigger: double-tap ⌘ alone — the second press must land within this window. Hold the second ⌘ to navigate, release to commit.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
        }
        .compatGroupedFormStyle()
    }
}

// MARK: - Apps (merged Pins + Colors)

// TODO: Apps 布局支持多 profile —— 现在只渲染单个 "Default" 绑定，
// 未来需要一个 profile 列表 + 切换器（"Default" / "Work" / "Gaming"...），
// 每个 profile 独立维护 pinnedBundleIDs / identityOverride。AppPreferences
// 已留了 `clearAllBindings()` 入口，以后按 profile 维度切桶即可。
private struct AppsTab: View {
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

    /// "Halo binding" card at the top of the Apps tab. Looks like a small
    /// app/profile chip — name, slot count, pinned count, and a Clear
    /// button. Today there's only ever one profile ("Default"); see the
    /// TODO above the type for the multi-profile shape we'll grow into.
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

// MARK: - About

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 0)

            Image(systemName: "circle.dashed.inset.filled")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.tint)

            VStack(spacing: 4) {
                Text("Halo").font(.largeTitle).bold()
                Text("v\(Halo.version)")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Text("Radial app launcher for macOS — point a direction, switch apps.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 360)

            HStack(spacing: 12) {
                Link("GitHub", destination: URL(string: "https://github.com/elonnzhang/Halo")!)
                Text("·").foregroundStyle(.tertiary)
                Link("License (MIT)", destination: URL(string: "https://github.com/elonnzhang/Halo/blob/main/LICENSE")!)
            }
            .font(.callout)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Hotkey capture

private struct HotkeyCaptureView: NSViewRepresentable {
    let prefs: AppPreferences
    let onCapture: () -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let v = KeyCaptureView()
        v.onCapture = { code, mods in
            prefs.hotkeyKeyCode = code
            prefs.hotkeyModifiers = mods
            onCapture()
        }
        return v
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
    }
}

private final class KeyCaptureView: NSView {
    var onCapture: ((UInt32, HotkeyModifiers) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        let modifiers = HotkeyModifiers(nsEventFlags: event.modifierFlags)
        guard !modifiers.isEmpty else {
            NSSound.beep()
            return
        }
        onCapture?(UInt32(event.keyCode), modifiers)
    }
}

extension HotkeyModifiers {
    init(nsEventFlags flags: NSEvent.ModifierFlags) {
        var s: HotkeyModifiers = []
        if flags.contains(.command) { s.insert(.command) }
        if flags.contains(.option)  { s.insert(.option) }
        if flags.contains(.control) { s.insert(.control) }
        if flags.contains(.shift)   { s.insert(.shift) }
        self = s
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

// MARK: - Glass chip

/// Compact "key cap" surface for the hotkey display. macOS 26+ uses Liquid
/// Glass; tinting the active state with the system accent color is semantic
/// — it signals "press a chord now" rather than decorating the chip. Older
/// systems fall back to the original gray fill. Compile-time gated behind
/// `#if compiler(>=6.3)` so CI runners with Xcode 16 still build.
private struct KeyCapChip: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        #if compiler(>=6.3)
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    active ? .regular.tint(.accentColor.opacity(0.35)) : .regular,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
        } else {
            legacyCap(content)
        }
        #else
        legacyCap(content)
        #endif
    }

    @ViewBuilder
    private func legacyCap(_ content: Content) -> some View {
        content.background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.gray.opacity(active ? 0.4 : 0.15))
        )
    }
}

// MARK: - Key code label

enum KeyName {
    static func label(for code: UInt32) -> String {
        switch code {
        case 49: return "Space"
        case 36: return "Return"
        case 48: return "Tab"
        case 51: return "Delete"
        case 53: return "Escape"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default:
            if let key = mapAlphaNumeric(code) { return key }
            return "key:\(code)"
        }
    }

    private static func mapAlphaNumeric(_ code: UInt32) -> String? {
        let table: [UInt32: String] = [
            0: "A", 11: "B", 8: "C", 2: "D", 14: "E", 3: "F", 5: "G", 4: "H",
            34: "I", 38: "J", 40: "K", 37: "L", 46: "M", 45: "N", 31: "O",
            35: "P", 12: "Q", 15: "R", 1: "S", 17: "T", 32: "U", 9: "V",
            13: "W", 7: "X", 16: "Y", 6: "Z",
            29: "0", 18: "1", 19: "2", 20: "3", 21: "4", 23: "5", 22: "6",
            26: "7", 28: "8", 25: "9",
        ]
        return table[code]
    }
}
