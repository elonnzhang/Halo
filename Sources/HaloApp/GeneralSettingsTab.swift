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
    @Binding var pane: GeneralSettingsPane
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var capturing = false

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabsHeader {
                SettingsSegmentedTabs(
                    labels: GeneralSettingsPane.allCases.map(\.title),
                    selectedIndex: GeneralSettingsPane.allCases.firstIndex(of: pane) ?? 0,
                    accessibilityLabel: NSLocalizedString("General settings", comment: ""),
                    onSelect: { index in pane = GeneralSettingsPane.allCases[index] }
                )
            }

            ZStack(alignment: .top) {
                if #available(macOS 13.0, *) {
                    nativeForm.id(pane).transition(.opacity)
                } else {
                    legacyForm.id(pane).transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .animation(.easeOut(duration: reduceMotion ? 0.05 : 0.14), value: pane)
        }
        .onChange(of: pane) { _ in capturing = false }
        .onDisappear { capturing = false }
        .frame(maxWidth: 760)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Native (macOS 13+)

    @available(macOS 13.0, *)
    @ViewBuilder
    private var nativeForm: some View {
        Form {
            // General is user-global behaviour, grouped top-down as
            // Summon & triggers -> Navigation -> Appearance -> Sound ->
            // Startup -> Diagnostics -> Language. Slot count, tint, and
            // ranking are per-profile (Apps tab); this tab only keeps a
            // pointer to them. "Show ALL profile" also lives under Apps
            // since it is a profile-scoped switch.
            if pane == .controls {
                Section {
                    Picker("Summon position", selection: Binding(
                        get: { prefs.summonPosition },
                        set: { prefs.summonPosition = $0 }
                    )) {
                        Text("At cursor").tag(SummonPosition.mouse)
                        Text("Screen center").tag(SummonPosition.center)
                    }
                    .pickerStyle(.segmented)

                    perProfilePointer

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
                    Text("Summon & triggers")
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
                } header: {
                    Text("Navigation")
                } footer: {
                    Text("Scroll wheel cycles slots with the highlighted one as anchor.")
                }
            }

            if pane == .appearance {
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

                Section {
                    geometryRow("Edge tilt",
                                value: Binding(
                                    get: { Double(prefs.lensTilt) },
                                    set: { prefs.lensTilt = CGFloat($0) }),
                                range: Self.lensTiltRange,
                                step: 1,
                                formatter: { "\(Int($0))°" })
                    Toggle("Match screen proportions", isOn: Binding(
                        get: { prefs.lensEllipseAuto },
                        set: { prefs.lensEllipseAuto = $0 }
                    ))
                    if !prefs.lensEllipseAuto {
                        geometryRow("Ellipse ratio",
                                    value: Binding(
                                        get: { Double(prefs.lensEllipseRatio) },
                                        set: { prefs.lensEllipseRatio = CGFloat($0) }),
                                    range: Self.lensEllipseRange,
                                    step: 0.05,
                                    formatter: { String(format: "%.2f : 1", $0) })
                    }
                    geometryRow("Edge fade",
                                value: Binding(
                                    get: { Double(prefs.lensRimFade) },
                                    set: { prefs.lensRimFade = CGFloat($0) }),
                                range: Self.lensRimFadeRange,
                                step: 0.02,
                                formatter: { "\(Int(($0 * 100).rounded()))%" })
                    HStack {
                        Spacer()
                        Button("Reset ALL grid") { prefs.resetLens() }
                    }
                } header: {
                    Text("ALL grid")
                } footer: {
                    Text("Edge tilt is how far icons turn away at the screen edge. The ellipse ratio stretches the lens along the screen's long side; 1 : 1 is a circle. Edge fade dims icons away from the middle.")
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
            }

            if pane == .system {
                Section("Startup") {
                    Toggle("Launch Halo at login", isOn: Binding(
                        get: { prefs.autostart },
                        set: {
                            prefs.autostart = $0
                            LaunchAgentManager.apply(enabled: $0)
                        }
                    ))
                }

                Section("Diagnostics") {
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
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private static let lensTiltRange = Double(AppPreferences.lensTiltRange.lowerBound)
        ... Double(AppPreferences.lensTiltRange.upperBound)
    private static let lensEllipseRange = Double(AppPreferences.lensEllipseRange.lowerBound)
        ... Double(AppPreferences.lensEllipseRange.upperBound)
    private static let lensRimFadeRange = Double(AppPreferences.lensRimFadeRange.lowerBound)
        ... Double(AppPreferences.lensRimFadeRange.upperBound)

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
                Slider(value: value, in: range, step: step)
                    .accessibilityLabel(Text(title))
                    .accessibilityValue(Text(formatter(value.wrappedValue)))
                    .frame(width: 200)
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
            // Slot count, tint, and ranking moved per-profile; legacy
            // form mirrors the native form's pointer.
            if pane == .controls {
                Section("Summon & triggers") {
                    Picker("Summon position", selection: Binding(
                        get: { prefs.summonPosition },
                        set: { prefs.summonPosition = $0 }
                    )) {
                        Text("At cursor").tag(SummonPosition.mouse)
                        Text("Screen center").tag(SummonPosition.center)
                    }
                    .pickerStyle(.segmented)
                    perProfilePointer
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
                }
            }

            if pane == .appearance {
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
                Section("ALL grid") {
                    HStack {
                        Text("Edge tilt")
                        Slider(value: Binding(
                            get: { Double(prefs.lensTilt) },
                            set: { prefs.lensTilt = CGFloat($0) }
                        ), in: Self.lensTiltRange, step: 1)
                        Text("\(Int(prefs.lensTilt))°")
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 54)
                    }
                    Toggle("Match screen proportions", isOn: Binding(
                        get: { prefs.lensEllipseAuto },
                        set: { prefs.lensEllipseAuto = $0 }
                    ))
                    if !prefs.lensEllipseAuto {
                        HStack {
                            Text("Ellipse ratio")
                            Slider(value: Binding(
                                get: { Double(prefs.lensEllipseRatio) },
                                set: { prefs.lensEllipseRatio = CGFloat($0) }
                            ), in: Self.lensEllipseRange, step: 0.05)
                            Text(String(format: "%.2f : 1", prefs.lensEllipseRatio))
                                .font(.system(.body, design: .monospaced))
                                .frame(width: 54)
                        }
                    }
                    HStack {
                        Text("Edge fade")
                        Slider(value: Binding(
                            get: { Double(prefs.lensRimFade) },
                            set: { prefs.lensRimFade = CGFloat($0) }
                        ), in: Self.lensRimFadeRange, step: 0.02)
                        Text("\(Int((prefs.lensRimFade * 100).rounded()))%")
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 54)
                    }
                    Button("Reset ALL grid") { prefs.resetLens() }
                }
                Section("Sound") {
                    Toggle("Enable sound effects", isOn: Binding(
                        get: { prefs.soundEffectsEnabled },
                        set: { prefs.soundEffectsEnabled = $0 }
                    ))
                }
            }

            if pane == .system {
                Section("Startup") {
                    Toggle("Launch Halo at login", isOn: Binding(
                        get: { prefs.autostart },
                        set: {
                            prefs.autostart = $0
                            LaunchAgentManager.apply(enabled: $0)
                        }
                    ))
                }
                Section("Diagnostics") {
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
        }
        .compatGroupedFormStyle()
    }

    /// One-line pointer surfaced under both the native and legacy
    /// forms' summon section. v1.3.0 moved slot count, ambient tint,
    /// and ranking strategy onto the active profile; this label tells
    /// users where the controls went and switches Settings to the Apps
    /// tab on click so they don't have to hunt for them.
    private var perProfilePointer: some View {
        Button {
            SettingsFocusCoordinator.shared.requestFocus(.apps)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 11))
                Text("Slots, tint, and ranking are per profile — set under Apps")
                    .font(.callout)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Switch to the Apps tab")
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
