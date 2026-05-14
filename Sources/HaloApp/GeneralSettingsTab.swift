import AppKit
import SwiftUI
import HaloCore
import HaloUI

/// General tab in the v1.1 sidebar settings panel. Six grouped sections,
/// top-to-bottom: 召唤 → 触发 → 导航 → 外观 → 启动 → 语言. Replaces the
/// pre-v1.1 General + Hotkey tabs.
struct GeneralTab: View {
    @ObservedObject var prefs: AppPreferences
    @State private var capturing = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                summonGroup
                triggerGroup
                navigationGroup
                appearanceGroup
                startupGroup
                languageGroup
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: Header

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("General").font(.system(size: 20, weight: .semibold))
            Spacer()
            Text("halo.prefs.*")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    // MARK: Summon

    @ViewBuilder
    private var summonGroup: some View {
        settingsGroup(title: "Summon position & ranking") {
            settingsRow("Slot count", isFirst: true) {
                Picker("", selection: Binding(
                    get: { prefs.slotCount },
                    set: { prefs.slotCount = $0 }
                )) {
                    ForEach([4, 6, 8, 10, 12], id: \.self) { Text("\($0)").tag($0) }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            settingsRow("Summon position") {
                Picker("", selection: Binding(
                    get: { prefs.summonPosition },
                    set: { prefs.summonPosition = $0 }
                )) {
                    Text("At cursor").tag(SummonPosition.mouse)
                    Text("Screen center").tag(SummonPosition.center)
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            settingsRow("Frequency profile") {
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
                .frame(width: 220)
            }
        }
    }

    // MARK: Trigger

    @ViewBuilder
    private var triggerGroup: some View {
        settingsGroup(
            title: "Trigger",
            footer: "Hold the chord to summon, release to commit. Or double-tap the auxiliary key — the second press must land within the gap window."
        ) {
            settingsRow("Summon hotkey", isFirst: true) {
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
                    .foregroundStyle(.tint)
                }
            }
            if capturing {
                HotkeyCaptureView(prefs: prefs) { capturing = false }
                    .frame(width: 1, height: 1)
            }
            settingsRow("Double-tap trigger") {
                Picker("", selection: Binding(
                    get: { prefs.doubleTapTrigger },
                    set: { prefs.doubleTapTrigger = $0 }
                )) {
                    ForEach(DoubleTapTrigger.allCases, id: \.self) { trigger in
                        Text(trigger.displayLabel).tag(trigger)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 200)
            }
            settingsRow("Double-tap gap") {
                HStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { prefs.cmdDoubleTapGap },
                            set: { prefs.cmdDoubleTapGap = $0 }
                        ),
                        in: 0.15...0.50,
                        step: 0.05
                    )
                    .frame(width: 180)
                    Text(String(format: "%.2f s", prefs.cmdDoubleTapGap))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .trailing)
                }
            }
        }
    }

    // MARK: Navigation

    @ViewBuilder
    private var navigationGroup: some View {
        settingsGroup(
            title: "Navigation",
            footer: "Scroll wheel cycles slots with the highlighted one as anchor. Digit keys 1–9 0 - = jump directly. Highlight frontmost falls back to 12 o'clock when the frontmost app isn't pinned."
        ) {
            settingsRow("Scroll to switch slots", isFirst: true) {
                Toggle("", isOn: Binding(
                    get: { prefs.scrollToSwitch },
                    set: { prefs.scrollToSwitch = $0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            settingsRow("Digit-key commit") {
                HStack(spacing: 8) {
                    Text("1 2 3 … 9 0 - =")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(0.06))
                        )
                    Toggle("", isOn: Binding(
                        get: { prefs.numberKeyCommit },
                        set: { prefs.numberKeyCommit = $0 }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                }
            }
            settingsRow("Highlight frontmost on summon") {
                Toggle("", isOn: Binding(
                    get: { prefs.highlightFrontmostOnSummon },
                    set: { prefs.highlightFrontmostOnSummon = $0 }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
        }
    }

    // MARK: Appearance

    @ViewBuilder
    private var appearanceGroup: some View {
        settingsGroup(
            title: "Appearance & wheel layout",
            footer: "Panel size is a renderer-time uniform scale (0.80–1.50x). Summon Halo to see the change take effect."
        ) {
            settingsRow("Panel size", isFirst: true) {
                HStack(spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { Double(prefs.panelScale) },
                            set: { prefs.panelScale = CGFloat($0) }
                        ),
                        in: 0.80...1.50,
                        step: 0.05
                    )
                    .frame(width: 180)
                    Text(String(format: "%.2f x", prefs.panelScale))
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(width: 54, alignment: .trailing)
                }
            }
            settingsRow("Halo diameter") {
                geometrySlider(value: Binding(
                    get: { Double(prefs.haloDiameter) },
                    set: { prefs.haloDiameter = CGFloat($0) }
                ), in: 280...440, step: 10, suffix: "pt")
            }
            settingsRow("Icon size") {
                geometrySlider(value: Binding(
                    get: { Double(prefs.iconSize) },
                    set: { prefs.iconSize = CGFloat($0) }
                ), in: 36...64, step: 2, suffix: "pt")
            }
            settingsRow("Icon distance") {
                let bounds = prefs.iconRadiusBounds
                geometrySlider(value: Binding(
                    get: { Double(prefs.iconRadius) },
                    set: { prefs.iconRadius = CGFloat($0) }
                ), in: Double(bounds.min)...Double(bounds.max), step: 2, suffix: "pt")
            }
            settingsRow("Reset layout") {
                Button("Reset wheel layout") { prefs.resetLayout() }
            }
        }
    }

    // MARK: Startup

    @ViewBuilder
    private var startupGroup: some View {
        settingsGroup(title: "Startup & diagnostics") {
            settingsRow("Launch Halo at login", isFirst: true) {
                Toggle("", isOn: Binding(
                    get: { prefs.autostart },
                    set: {
                        prefs.autostart = $0
                        LaunchAgentManager.apply(enabled: $0)
                    }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
            }
            settingsRow("Welcome guide") {
                Button("Replay") {
                    (NSApp.delegate as? AppDelegate)?.replayWelcome()
                }
            }
            settingsRow("Onboarding overlay") {
                Button("Reset") { prefs.resetOnboarding() }
            }
            settingsRow("Diagnostic log") {
                Button("Export…") { exportDiagnostics() }
            }
        }
    }

    // MARK: Language

    @ViewBuilder
    private var languageGroup: some View {
        settingsGroup(
            title: "Language",
            footer: "Restart Halo for the language change to take effect."
        ) {
            settingsRow("Display language", isFirst: true) {
                Picker("", selection: Binding(
                    get: { prefs.appLanguageOverride ?? "system" },
                    set: { prefs.appLanguageOverride = ($0 == "system" ? nil : $0) }
                )) {
                    Text("System").tag("system")
                    Text("English").tag("en")
                    Text("简体中文").tag("zh-Hans")
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .frame(width: 200)
            }
        }
    }

    // MARK: Row primitives

    @ViewBuilder
    private func settingsGroup<Content: View>(
        title: LocalizedStringKey,
        footer: LocalizedStringKey? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.bottom, 4)
                .padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .background(rowBackground)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                )
            if let footer = footer {
                Text(footer)
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .padding(.horizontal, 4)
                    .padding(.top, 6)
            }
        }
    }

    @ViewBuilder
    private func settingsRow<Trailing: View>(
        _ label: LocalizedStringKey,
        isFirst: Bool = false,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            trailing()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .overlay(alignment: .top) {
            // Top divider for every row except the first — keeps the group
            // header tight against the rounded card.
            if !isFirst {
                Rectangle()
                    .fill(Color.primary.opacity(0.06))
                    .frame(height: 0.5)
            }
        }
    }

    private var rowBackground: Color {
        Color(NSColor.controlBackgroundColor)
    }

    @ViewBuilder
    private func geometrySlider(
        value: Binding<Double>,
        in range: ClosedRange<Double>,
        step: Double,
        suffix: String
    ) -> some View {
        HStack(spacing: 8) {
            Slider(value: value, in: range, step: step).frame(width: 180)
            Text("\(Int(value.wrappedValue)) \(suffix)")
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 54, alignment: .trailing)
        }
    }

    /// Pulls the last hour of unified-log entries under the Halo
    /// subsystem into `~/Downloads/Halo-diagnostic-<ts>.log` and reveals it
    /// in Finder. Surfaces failure via NSAlert.
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
