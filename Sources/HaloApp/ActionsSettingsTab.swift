import SwiftUI
import AppKit
import HaloCore
import HaloUI

/// Settings → Actions: bind ONE custom Action Arc chip per app.
///
/// The arc is built into Halo as 3 fixed builtins (close / fullscreen / hide)
/// plus a 4th user-bound custom. This tab manages that 4th chip per app.
/// `AppPreferences.actions(forBundleID:)` still stores `[HaloAction]` but
/// the arc renderer reads only `.first`; users can only have one here.
struct ActionsTab: View {
    @ObservedObject var prefs: AppPreferences
    @Binding var focusBundleID: String?

    @State private var selectedBundleID: String?
    @State private var showingAppPicker = false
    @State private var editing: ActionEditorTarget?

    var body: some View {
        HStack(spacing: 0) {
            appList
                .frame(width: 220)
            Divider()
            actionDetail
                .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 8)
        .onAppear(perform: applyFocus)
        .onChange(of: focusBundleID) { _ in applyFocus() }
        .sheet(isPresented: $showingAppPicker) {
            AppPickerSheet { picked in
                showingAppPicker = false
                if let id = picked {
                    selectedBundleID = id
                    // Open the editor immediately so first-time users land
                    // in the form instead of staring at an empty pane.
                    editing = ActionEditorTarget(bundleID: id, existing: nil)
                }
            }
        }
        .sheet(item: $editing) { target in
            ActionEditorSheet(target: target) { saved in
                editing = nil
                guard let saved = saved else { return }
                prefs.setActions([saved], forBundleID: target.bundleID)
            }
        }
    }

    private func applyFocus() {
        guard let id = focusBundleID else { return }
        selectedBundleID = id
        focusBundleID = nil
    }

    // MARK: - App list (left column)

    private var appList: some View {
        VStack(alignment: .leading, spacing: 0) {
            sectionHeader("Apps")
            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(sortedBundleIDs, id: \.self) { id in
                        appRow(id)
                    }
                    if sortedBundleIDs.isEmpty {
                        Text("No apps configured.\nTap + to bind a custom action.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 12)
                            .padding(.top, 28)
                    }
                }
                .padding(.vertical, 4)
            }
            Divider()
            Button {
                showingAppPicker = true
            } label: {
                Label("Add app…", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func appRow(_ id: String) -> some View {
        let isSelected = id == selectedBundleID
        let hasCustom = prefs.actions(forBundleID: id).first != nil
        return Button {
            selectedBundleID = id
        } label: {
            HStack(spacing: 9) {
                if let icon = AppIconResolver.icon(for: id) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.18))
                        .frame(width: 20, height: 20)
                }
                Text(displayName(for: id))
                    .lineLimit(1)
                Spacer()
                Circle()
                    .fill(hasCustom ? Color.accentColor : Color.clear)
                    .frame(width: 6, height: 6)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isSelected ? Color.accentColor.opacity(0.20) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Detail (right column)

    private var actionDetail: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let id = selectedBundleID {
                detailHeader(for: id)
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        chipExplainer
                        currentCustomRow(for: id)
                    }
                    .padding(.vertical, 14)
                    .padding(.horizontal, 16)
                }
            } else {
                VStack(spacing: 12) {
                    Image(systemName: "bolt.circle")
                        .font(.system(size: 36, weight: .light))
                        .foregroundStyle(.tertiary)
                    Text("Pick an app on the left, or add one")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
        }
    }

    private func detailHeader(for id: String) -> some View {
        HStack(spacing: 10) {
            if let icon = AppIconResolver.icon(for: id) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: 28, height: 28)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(displayName(for: id))
                    .font(.headline)
                Text(id)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(role: .destructive) {
                prefs.setActions([], forBundleID: id)
                if selectedBundleID == id { selectedBundleID = nil }
            } label: {
                Label("Remove app", systemImage: "trash")
                    .labelStyle(.iconOnly)
            }
            .help("Remove this app's custom action")
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Show the arc layout so the user knows where the custom chip sits.
    private var chipExplainer: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Arc chips")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            HStack(spacing: 12) {
                chipPreview(symbol: "power", color: Color(red: 1, green: 0.27, blue: 0.23), label: "Quit", builtin: true)
                chipPreview(symbol: "arrow.up.left.and.arrow.down.right", color: Color(red: 0.97, green: 0.71, blue: 0), label: "Fullscreen", builtin: true)
                chipPreview(symbol: "moon", color: Color(red: 0.23, green: 0.51, blue: 0.96), label: "Hide", builtin: true)
                chipPreview(symbol: "wand.and.stars", color: Color(red: 0.11, green: 0.73, blue: 0.33), label: "Custom", builtin: false, isCustomSlot: true)
            }
            Text("Three system chips are fixed across every app. The fourth is yours.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func chipPreview(
        symbol: String,
        color: Color,
        label: String,
        builtin: Bool,
        isCustomSlot: Bool = false
    ) -> some View {
        VStack(spacing: 4) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.55))
                    .overlay(Circle().strokeBorder(isCustomSlot ? color : color.opacity(0.3), lineWidth: isCustomSlot ? 1.4 : 0.8))
                    .frame(width: 36, height: 36)
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(color)
            }
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(builtin ? .secondary : .primary)
        }
    }

    private func currentCustomRow(for id: String) -> some View {
        let current = prefs.actions(forBundleID: id).first
        return VStack(alignment: .leading, spacing: 6) {
            Text("Your custom chip")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            if let action = current {
                HStack(spacing: 10) {
                    Image(systemName: action.effectiveSFSymbol)
                        .frame(width: 22, height: 22)
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(action.label).font(.system(size: 13, weight: .semibold))
                        Text(payloadPreview(action))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    Spacer()
                    Button("Edit") {
                        editing = ActionEditorTarget(bundleID: id, existing: action)
                    }
                    Button(role: .destructive) {
                        prefs.setActions([], forBundleID: id)
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
            } else {
                Button {
                    editing = ActionEditorTarget(bundleID: id, existing: nil)
                } label: {
                    Label("Add custom action…", systemImage: "plus.circle.fill")
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.06)))
            }
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 8)
            .padding(.bottom, 4)
    }

    // MARK: - Helpers

    private var sortedBundleIDs: [String] {
        prefs.actionBoundBundleIDs.sorted {
            displayName(for: $0).localizedCaseInsensitiveCompare(displayName(for: $1)) == .orderedAscending
        }
    }

    private func displayName(for id: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            return (url.lastPathComponent as NSString).deletingPathExtension
        }
        return id
    }

    private func payloadPreview(_ action: HaloAction) -> String {
        switch action.kind {
        case .openFolder:  return action.payload
        case .openURL:     return action.payload
        case .runShortcut: return "⌥ Shortcut · \(action.payload)"
        }
    }
}

/// Identifies which custom-chip the editor is targeting. `existing: nil`
/// means "add new".
struct ActionEditorTarget: Identifiable {
    let id = UUID()
    let bundleID: String
    let existing: HaloAction?
}

/// Add / edit the single user-custom chip for an app.
struct ActionEditorSheet: View {
    let target: ActionEditorTarget
    let onFinish: (HaloAction?) -> Void

    @State private var label: String
    @State private var kind: HaloActionKind
    @State private var payload: String
    @State private var symbol: String

    init(target: ActionEditorTarget, onFinish: @escaping (HaloAction?) -> Void) {
        self.target = target
        self.onFinish = onFinish
        let existing = target.existing
        _label = State(initialValue: existing?.label ?? "")
        _kind = State(initialValue: existing?.kind ?? .openFolder)
        _payload = State(initialValue: existing?.payload ?? "")
        _symbol = State(initialValue: existing?.sfSymbol ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(target.existing == nil ? "Add custom action" : "Edit custom action")
                .font(.title3.bold())

            Form {
                TextField("Label", text: $label)
                Picker("Kind", selection: $kind) {
                    Text("Open folder").tag(HaloActionKind.openFolder)
                    Text("Open URL").tag(HaloActionKind.openURL)
                    Text("Run Shortcut").tag(HaloActionKind.runShortcut)
                }
                .pickerStyle(.segmented)

                VStack(alignment: .leading, spacing: 4) {
                    TextField(payloadPlaceholder, text: $payload)
                    if !payloadHint.isEmpty {
                        Text(payloadHint)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    TextField("SF Symbol (optional)", text: $symbol)
                    Text("Default: \(kind.defaultSFSymbol)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .compatGroupedFormStyle()

            HStack {
                Spacer()
                Button("Cancel") { onFinish(nil) }
                    .keyboardShortcut(.cancelAction)
                Button(target.existing == nil ? "Add" : "Save") {
                    onFinish(buildAction())
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 460)
    }

    private var isValid: Bool {
        !label.trimmingCharacters(in: .whitespaces).isEmpty &&
        !payload.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var payloadPlaceholder: String {
        switch kind {
        case .openFolder:  return "~/Downloads or /Users/.../Code"
        case .openURL:     return "https://github.com/halo or any URL"
        case .runShortcut: return "Shortcut name (e.g. Daily Plan)"
        }
    }

    private var payloadHint: String {
        switch kind {
        case .openFolder:  return "`~` is expanded at run time. Folder must exist."
        case .openURL:     return "Any scheme NSWorkspace accepts: https://, mailto:, raycast://, etc."
        case .runShortcut: return "Matches by exact name in the Shortcuts app."
        }
    }

    private func buildAction() -> HaloAction {
        HaloAction(
            id: target.existing?.id ?? UUID(),
            label: label.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            payload: payload.trimmingCharacters(in: .whitespacesAndNewlines),
            sfSymbol: symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : symbol
        )
    }
}
