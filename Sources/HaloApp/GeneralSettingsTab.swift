import AppKit
import SwiftUI
import HaloCore
import HaloUI

/// General tab in the v1.1 sidebar settings panel. On macOS 13+ the
/// content is a native `Form(.grouped)` so the rows pick up the system
/// Settings look — translucent grouped cards, accent-tinted controls,
/// Liquid Glass on macOS 26. macOS 12 falls back to a plain `Form` via
/// `compatGroupedFormStyle()` from HaloUI.
struct GeneralTab: View {
    @ObservedObject var prefs: AppPreferences
    @State private var capturing = false

    var body: some View {
        if #available(macOS 13.0, *) {
            nativeForm
        } else {
            legacyForm
        }
    }

    // MARK: - Native (macOS 13+)

    @available(macOS 13.0, *)
    @ViewBuilder
    private var nativeForm: some View {
        Form {
            // Slot count moved per-profile; see Apps tab → "Slots
            // for this profile". This section now only carries
            // settings that stay user-global.
            Section("Summon position & ranking") {
                Picker("Summon position", selection: Binding(
                    get: { prefs.summonPosition },
                    set: { prefs.summonPosition = $0 }
                )) {
                    Text("At cursor").tag(SummonPosition.mouse)
                    Text("Screen center").tag(SummonPosition.center)
                }
                .pickerStyle(.segmented)

                Picker("Frequency profile", selection: Binding(
                    get: { prefs.frequencyProfile },
                    set: { prefs.frequencyProfile = $0 }
                )) {
                    Text("MFU").tag(FrequencyProfile.mfuOnly)
                    Text("Balanced").tag(FrequencyProfile.balanced)
                    Text("MRU").tag(FrequencyProfile.mruOnly)
                }
                .pickerStyle(.segmented)
            }

            Section {
                LabeledContent {
                    HStack(spacing: 8) {
                        Text("\(prefs.hotkeyModifiers.symbols)\(KeyName.label(for: prefs.hotkeyKeyCode))")
                            .font(.system(.body, design: .monospaced))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .modifier(KeyCapChip(active: capturing))
                        Button(capturing ? "Press chord…" : "Rebind") {
                            capturing.toggle()
                        }
                        Button("Reset") {
                            prefs.hotkeyKeyCode = 49
                            prefs.hotkeyModifiers = [.command, .option]
                        }
                        .buttonStyle(.borderless)
                    }
                } label: {
                    Text("Summon hotkey")
                }
                if capturing {
                    HotkeyCaptureView(prefs: prefs) { capturing = false }
                        .frame(width: 1, height: 1)
                }

                Picker("Double-tap trigger", selection: Binding(
                    get: { prefs.doubleTapTrigger },
                    set: { prefs.doubleTapTrigger = $0 }
                )) {
                    ForEach(DoubleTapTrigger.allCases, id: \.self) { trigger in
                        Text(trigger.displayLabel).tag(trigger)
                    }
                }

                LabeledContent {
                    HStack(spacing: 8) {
                        Slider(
                            value: Binding(
                                get: { prefs.cmdDoubleTapGap },
                                set: { prefs.cmdDoubleTapGap = $0 }
                            ),
                            in: 0.15...0.50,
                            step: 0.05
                        )
                        .frame(width: 200)
                        Text(String(format: "%.2f s", prefs.cmdDoubleTapGap))
                            .font(.system(.body, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .frame(width: 54, alignment: .trailing)
                    }
                } label: {
                    Text("Double-tap gap")
                }
            } header: {
                Text("Trigger")
            } footer: {
                Text("Hold the chord to summon, release to commit. Or double-tap the auxiliary key — the second press must land within the gap window.")
            }

            Section {
                Toggle("Scroll to switch slots", isOn: Binding(
                    get: { prefs.scrollToSwitch },
                    set: { prefs.scrollToSwitch = $0 }
                ))
                Toggle(isOn: Binding(
                    get: { prefs.numberKeyCommit },
                    set: { prefs.numberKeyCommit = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Digit-key commit")
                        Text("1 2 3 … 9 0 - = jump directly to the matching slot.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: Binding(
                    get: { prefs.highlightFrontmostOnSummon },
                    set: { prefs.highlightFrontmostOnSummon = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Highlight frontmost on summon")
                        Text("Falls back to 12 o'clock when the frontmost app isn't pinned.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle(isOn: Binding(
                    get: { prefs.showAllProfile },
                    set: { prefs.showAllProfile = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Show ALL profile")
                        Text("Adds a built-in profile that opens a watchOS-style grid of every installed app. Tab to switch to it.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Navigation")
            } footer: {
                Text("Scroll wheel cycles slots with the highlighted one as anchor.")
            }

            Section {
                Toggle(isOn: Binding(
                    get: { prefs.soundEffectsEnabled },
                    set: { prefs.soundEffectsEnabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Enable sound effects")
                        Text("Plays on summon, slot slide, and commit. Uses system sounds.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Sound")
            }

            Section {
                Picker("Theme", selection: Binding(
                    get: { prefs.appearanceMode },
                    set: { prefs.appearanceMode = $0 }
                )) {
                    Text("System").tag(AppearanceMode.system)
                    Text("Light").tag(AppearanceMode.light)
                    Text("Dark").tag(AppearanceMode.dark)
                }
                .pickerStyle(.segmented)

                geometryRow("Panel size",
                            value: Binding(
                                get: { Double(prefs.panelScale) },
                                set: { prefs.panelScale = CGFloat($0) }),
                            range: 0.80...1.50, step: 0.05,
                            formatter: { String(format: "%.2f x", $0) })
                geometryRow("Halo diameter",
                            value: Binding(
                                get: { Double(prefs.haloDiameter) },
                                set: { prefs.haloDiameter = CGFloat($0) }),
                            range: 280...440, step: 10,
                            formatter: { "\(Int($0)) pt" })
                geometryRow("Icon size",
                            value: Binding(
                                get: { Double(prefs.iconSize) },
                                set: { prefs.iconSize = CGFloat($0) }),
                            range: 36...64, step: 2,
                            formatter: { "\(Int($0)) pt" })
                let bounds = prefs.iconRadiusBounds
                geometryRow("Icon distance",
                            value: Binding(
                                get: { Double(prefs.iconRadius) },
                                set: { prefs.iconRadius = CGFloat($0) }),
                            range: Double(bounds.min)...Double(bounds.max),
                            step: 2,
                            formatter: { "\(Int($0)) pt" })

                HStack {
                    Spacer()
                    Button("Reset wheel layout") { prefs.resetLayout() }
                }
            } header: {
                Text("Appearance & wheel layout")
            } footer: {
                Text("Theme applies app-wide — Settings, Halo wheel, welcome card, and alerts all follow.")
            }

            Section("Startup & diagnostics") {
                Toggle("Launch Halo at login", isOn: Binding(
                    get: { prefs.autostart },
                    set: {
                        prefs.autostart = $0
                        LaunchAgentManager.apply(enabled: $0)
                    }
                ))
                LabeledContent("Welcome guide") {
                    Button("Replay") {
                        (NSApp.delegate as? AppDelegate)?.replayWelcome()
                    }
                }
                LabeledContent("Onboarding overlay") {
                    Button("Reset") { prefs.resetOnboarding() }
                }
                LabeledContent("Diagnostic log") {
                    Button("Export…") { exportDiagnostics() }
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
            } header: {
                Text("Language")
            } footer: {
                Text("Restart Halo for the language change to take effect.")
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    @available(macOS 13.0, *)
    @ViewBuilder
    private func geometryRow(
        _ title: LocalizedStringKey,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        step: Double,
        formatter: (Double) -> String
    ) -> some View {
        LabeledContent {
            HStack(spacing: 8) {
                Slider(value: value, in: range, step: step).frame(width: 200)
                Text(formatter(value.wrappedValue))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 54, alignment: .trailing)
            }
        } label: {
            Text(title)
        }
    }

    // MARK: - Legacy (macOS 12 fallback)

    @ViewBuilder
    private var legacyForm: some View {
        Form {
            // Slot count moved per-profile (see Apps tab); keep the
            // section but drop the slot-count picker on the macOS 12
            // fallback form too.
            Section("Summon position & ranking") {
                Picker("Summon position", selection: Binding(
                    get: { prefs.summonPosition },
                    set: { prefs.summonPosition = $0 }
                )) {
                    Text("At cursor").tag(SummonPosition.mouse)
                    Text("Screen center").tag(SummonPosition.center)
                }
                .pickerStyle(.segmented)
                Picker("Frequency profile", selection: Binding(
                    get: { prefs.frequencyProfile },
                    set: { prefs.frequencyProfile = $0 }
                )) {
                    Text("MFU").tag(FrequencyProfile.mfuOnly)
                    Text("Balanced").tag(FrequencyProfile.balanced)
                    Text("MRU").tag(FrequencyProfile.mruOnly)
                }
                .pickerStyle(.segmented)
            }
            Section("Trigger") {
                HStack {
                    Text("Summon hotkey")
                    Spacer()
                    Text("\(prefs.hotkeyModifiers.symbols)\(KeyName.label(for: prefs.hotkeyKeyCode))")
                        .font(.system(.body, design: .monospaced))
                    Button(capturing ? "Press chord…" : "Rebind") { capturing.toggle() }
                }
                if capturing {
                    HotkeyCaptureView(prefs: prefs) { capturing = false }
                        .frame(width: 1, height: 1)
                }
                Picker("Double-tap trigger", selection: Binding(
                    get: { prefs.doubleTapTrigger },
                    set: { prefs.doubleTapTrigger = $0 }
                )) {
                    ForEach(DoubleTapTrigger.allCases, id: \.self) { trigger in
                        Text(trigger.displayLabel).tag(trigger)
                    }
                }
                HStack {
                    Text("Double-tap gap")
                    Slider(
                        value: Binding(
                            get: { prefs.cmdDoubleTapGap },
                            set: { prefs.cmdDoubleTapGap = $0 }
                        ),
                        in: 0.15...0.50, step: 0.05
                    )
                    Text(String(format: "%.2f s", prefs.cmdDoubleTapGap))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 54)
                }
            }
            Section("Navigation") {
                Toggle("Scroll to switch slots", isOn: Binding(
                    get: { prefs.scrollToSwitch },
                    set: { prefs.scrollToSwitch = $0 }
                ))
                Toggle("Digit-key commit", isOn: Binding(
                    get: { prefs.numberKeyCommit },
                    set: { prefs.numberKeyCommit = $0 }
                ))
                Toggle("Highlight frontmost on summon", isOn: Binding(
                    get: { prefs.highlightFrontmostOnSummon },
                    set: { prefs.highlightFrontmostOnSummon = $0 }
                ))
                Toggle("Show ALL profile", isOn: Binding(
                    get: { prefs.showAllProfile },
                    set: { prefs.showAllProfile = $0 }
                ))
            }
            Section("Sound") {
                Toggle("Enable sound effects", isOn: Binding(
                    get: { prefs.soundEffectsEnabled },
                    set: { prefs.soundEffectsEnabled = $0 }
                ))
            }
            Section("Appearance & wheel layout") {
                Picker("Theme", selection: Binding(
                    get: { prefs.appearanceMode },
                    set: { prefs.appearanceMode = $0 }
                )) {
                    Text("System").tag(AppearanceMode.system)
                    Text("Light").tag(AppearanceMode.light)
                    Text("Dark").tag(AppearanceMode.dark)
                }
                .pickerStyle(.segmented)
                HStack {
                    Text("Panel size")
                    Slider(value: Binding(
                        get: { Double(prefs.panelScale) },
                        set: { prefs.panelScale = CGFloat($0) }
                    ), in: 0.80...1.50, step: 0.05)
                    Text(String(format: "%.2f x", prefs.panelScale))
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 54)
                }
                HStack {
                    Text("Halo diameter")
                    Slider(value: Binding(
                        get: { Double(prefs.haloDiameter) },
                        set: { prefs.haloDiameter = CGFloat($0) }
                    ), in: 280...440, step: 10)
                    Text("\(Int(prefs.haloDiameter)) pt")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 54)
                }
                HStack {
                    Text("Icon size")
                    Slider(value: Binding(
                        get: { Double(prefs.iconSize) },
                        set: { prefs.iconSize = CGFloat($0) }
                    ), in: 36...64, step: 2)
                    Text("\(Int(prefs.iconSize)) pt")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 54)
                }
                let bounds = prefs.iconRadiusBounds
                HStack {
                    Text("Icon distance")
                    Slider(value: Binding(
                        get: { Double(prefs.iconRadius) },
                        set: { prefs.iconRadius = CGFloat($0) }
                    ), in: Double(bounds.min)...Double(bounds.max), step: 2)
                    Text("\(Int(prefs.iconRadius)) pt")
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 54)
                }
                Button("Reset wheel layout") { prefs.resetLayout() }
            }
            Section("Startup & diagnostics") {
                Toggle("Launch Halo at login", isOn: Binding(
                    get: { prefs.autostart },
                    set: {
                        prefs.autostart = $0
                        LaunchAgentManager.apply(enabled: $0)
                    }
                ))
                Button("Replay welcome guide") {
                    (NSApp.delegate as? AppDelegate)?.replayWelcome()
                }
                Button("Reset onboarding overlay") { prefs.resetOnboarding() }
                Button("Export diagnostic log…") { exportDiagnostics() }
            }
            Section("Language") {
                Picker("Display language", selection: Binding(
                    get: { prefs.appLanguageOverride ?? "system" },
                    set: { prefs.appLanguageOverride = ($0 == "system" ? nil : $0) }
                )) {
                    Text("System").tag("system")
                    Text("English").tag("en")
                    Text("简体中文").tag("zh-Hans")
                }
            }
        }
        .compatGroupedFormStyle()
    }

    /// Pulls the last hour of unified-log entries under the Halo subsystem
    /// into `~/Downloads/Halo-diagnostic-<ts>.log` and reveals it in Finder.
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
}

// MARK: - Hotkey capture

struct HotkeyCaptureView: NSViewRepresentable {
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

final class KeyCaptureView: NSView {
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

// MARK: - Glass chip

/// Compact "key cap" surface for the hotkey display. macOS 26+ uses Liquid
/// Glass; tinting the active state with the system accent color signals
/// "press a chord now". Older systems fall back to a gray fill.
struct KeyCapChip: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(
                    active ? .regular.tint(.accentColor.opacity(0.35)) : .regular,
                    in: RoundedRectangle(cornerRadius: 6, style: .continuous)
                )
        } else {
            legacyCap(content)
        }
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
