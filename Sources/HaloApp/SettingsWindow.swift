import AppKit
import SwiftUI
import HaloCore
import HaloUI

@MainActor
final class SettingsWindowController {
    let window: NSWindow
    private let prefs: AppPreferences
    private let refresh: () -> Void

    init(prefs: AppPreferences, refreshHandler: @escaping () -> Void) {
        self.prefs = prefs
        self.refresh = refreshHandler

        let host = NSHostingController(rootView: SettingsRootView(prefs: prefs,
                                                                  onChange: refreshHandler))
        let w = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 540),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        w.title = "Halo · Settings"
        w.contentViewController = host
        w.isReleasedWhenClosed = false
        w.center()
        self.window = w
    }

    func show() {
        NSApp.setActivationPolicy(.regular)  // make window appear & take focus
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        WindowCloseObserver.attach(window: window) {
            // Return to menu-bar-only once Settings closes.
            NSApp.setActivationPolicy(.accessory)
        }
    }
}

/// Watches an NSWindow for its close notification so we can flip the
/// activation policy back to .accessory without subclassing the window.
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

    // No deinit: willCloseNotification is a single-shot event and removing the
    // dictionary entry frees this instance; the NotificationCenter token's only
    // remaining ref is from inside the handler block, which has already run.
}

// MARK: - SwiftUI root

struct SettingsRootView: View {
    @ObservedObject var prefs: AppPreferences
    let onChange: () -> Void

    var body: some View {
        TabView {
            BehaviorTab(prefs: prefs, onChange: onChange)
                .tabItem { Label("Behavior", systemImage: "slider.horizontal.3") }
            HotkeyTab(prefs: prefs)
                .tabItem { Label("Hotkey", systemImage: "command") }
            PinsTab(prefs: prefs, onChange: onChange)
                .tabItem { Label("Pins", systemImage: "pin") }
            ColorsTab(prefs: prefs, onChange: onChange)
                .tabItem { Label("Colors", systemImage: "paintpalette") }
            AboutTab()
                .tabItem { Label("About", systemImage: "info.circle") }
        }
        .padding(20)
        .frame(width: 560, height: 540)
    }
}

private struct BehaviorTab: View {
    @ObservedObject var prefs: AppPreferences
    let onChange: () -> Void

    var body: some View {
        Form {
            Picker("Slot count (N)", selection: Binding(
                get: { prefs.slotCount },
                set: { prefs.slotCount = $0; onChange() }
            )) {
                ForEach([4, 6, 8, 10, 12], id: \.self) { n in
                    Text("\(n)").tag(n)
                }
            }
            .pickerStyle(.segmented)

            Picker("Frequency profile", selection: Binding(
                get: { prefs.frequencyProfile },
                set: { prefs.frequencyProfile = $0; onChange() }
            )) {
                Text("MFU only").tag(FrequencyProfile.mfuOnly)
                Text("Balanced").tag(FrequencyProfile.balanced)
                Text("MRU only").tag(FrequencyProfile.mruOnly)
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

            Toggle("Launch Halo at login", isOn: Binding(
                get: { prefs.autostart },
                set: { prefs.autostart = $0; LaunchAgentManager.apply(enabled: $0) }
            ))

            Button("Reset onboarding overlay") {
                prefs.resetOnboarding()
            }
        }
        .formStyle(.grouped)
    }
}

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
                Button("Reset to ⌘⌥Space") {
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
        .formStyle(.grouped)
    }
}

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

private extension HotkeyModifiers {
    init(nsEventFlags flags: NSEvent.ModifierFlags) {
        var s: HotkeyModifiers = []
        if flags.contains(.command) { s.insert(.command) }
        if flags.contains(.option)  { s.insert(.option) }
        if flags.contains(.control) { s.insert(.control) }
        if flags.contains(.shift)   { s.insert(.shift) }
        self = s
    }
}

private struct PinsTab: View {
    @ObservedObject var prefs: AppPreferences
    let onChange: () -> Void

    var body: some View {
        Form {
            Section {
                ForEach(0..<prefs.slotCount, id: \.self) { i in
                    PinRow(slot: i, prefs: prefs, onChange: onChange)
                }
            } header: {
                Text("Pin a specific app to a slot, or leave Auto to let frequency choose.")
                    .foregroundStyle(.secondary)
                    .font(.callout)
            }
            if !prefs.overflowPinnedBundleIDs.isEmpty {
                Section("Hidden pins (slot count too low)") {
                    ForEach(prefs.overflowPinnedBundleIDs, id: \.self) { id in
                        Text(id).font(.system(.callout, design: .monospaced))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PinRow: View {
    let slot: Int
    @ObservedObject var prefs: AppPreferences
    let onChange: () -> Void
    @State private var pickerOpen = false

    var body: some View {
        HStack {
            Text("Slot \(slot)")
                .font(.system(.body, design: .monospaced))
                .frame(width: 60, alignment: .leading)

            let current = prefs.pinnedBundleIDs[safe: slot] ?? nil
            if let id = current,
               let icon = AppIconResolver.icon(for: id) {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                Text(displayName(for: id))
            } else {
                Image(systemName: "circle.dashed")
                    .foregroundStyle(.secondary)
                Text("Auto")
                    .foregroundStyle(.secondary)
            }

            Spacer()
            Button("Pick…") { pickerOpen = true }
            if current != nil {
                Button("Clear") {
                    prefs.setPinnedBundleID(nil, at: slot)
                    onChange()
                }
            }
        }
        .sheet(isPresented: $pickerOpen) {
            AppPickerSheet { picked in
                if let id = picked {
                    prefs.setPinnedBundleID(id, at: slot)
                    onChange()
                }
                pickerOpen = false
            }
        }
    }

    private func displayName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return bundleID }
        return (url.lastPathComponent as NSString).deletingPathExtension
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}

private struct AppPickerSheet: View {
    let onPick: (String?) -> Void
    @State private var apps: [(bundleID: String, name: String, url: URL)] = []
    @State private var search = ""

    var body: some View {
        NavigationStack {
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

private struct ColorsTab: View {
    @ObservedObject var prefs: AppPreferences
    let onChange: () -> Void

    var body: some View {
        let pinned = prefs.pinnedBundleIDs.compactMap { $0 }
        Form {
            Section {
                if pinned.isEmpty {
                    Text("Pin apps under Pins to override their identity color.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(pinned, id: \.self) { id in
                        ColorRow(bundleID: id, prefs: prefs, onChange: onChange)
                    }
                }
            } header: {
                Text("Override the auto-extracted identity color for any pinned app. Click the swatch to pick; Reset returns to the icon-derived color.")
                    .foregroundStyle(.secondary).font(.callout)
            }
        }
        .formStyle(.grouped)
    }
}

private struct ColorRow: View {
    let bundleID: String
    @ObservedObject var prefs: AppPreferences
    let onChange: () -> Void
    @State private var swatch: Color = .gray

    var body: some View {
        HStack {
            if let icon = AppIconResolver.icon(for: bundleID) {
                Image(nsImage: icon).resizable().frame(width: 20, height: 20)
            }
            Text(displayName)
            Spacer()
            ColorPicker("", selection: $swatch, supportsOpacity: false)
                .labelsHidden()
                .onChange(of: swatch) { _, new in
                    if let identity = IdentityColor.fromSwiftUI(new) {
                        prefs.setIdentityOverride(identity, for: bundleID)
                        onChange()
                    }
                }
            Button("Reset") {
                prefs.setIdentityOverride(nil, for: bundleID)
                onChange()
            }
        }
        .onAppear {
            if let override = prefs.identityOverride(for: bundleID) {
                swatch = override.swiftUIColor
            } else {
                swatch = .gray
            }
        }
    }

    private var displayName: String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return bundleID }
        return (url.lastPathComponent as NSString).deletingPathExtension
    }
}

private struct AboutTab: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "circle.dashed.inset.filled")
                .font(.system(size: 64, weight: .light))
                .foregroundStyle(.tint)
            Text("Halo").font(.largeTitle).bold()
            Text("v\(Halo.version) · radial app launcher for macOS")
                .foregroundStyle(.secondary)
            Text("Hold the hotkey, point a direction, release.")
                .foregroundStyle(.secondary)
                .font(.callout)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Glass chip

/// Compact "key cap" surface for the hotkey display. macOS 26+ uses Liquid
/// Glass; tinting the active state with the system accent color is semantic
/// — it signals "press a chord now" rather than decorating the chip. Older
/// systems fall back to the original gray fill.
private struct KeyCapChip: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    active ? .regular.tint(.accentColor.opacity(0.35)) : .regular,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
        } else {
            content.background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.gray.opacity(active ? 0.4 : 0.15))
            )
        }
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
