import SwiftUI
import AppKit
import HaloCore
import HaloUI

/// Per-app Action Ring bindings (Settings → Actions).
///
/// Left column: all bundleIDs that have at least one bound action, plus an
/// "Add app…" button that surfaces `AppPickerSheet`.
/// Right column: the action list for the selected app, with reorder /
/// edit / delete and an "Add action…" button that opens
/// `ActionEditorSheet`.
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
            actionList
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
                    // on a populated form instead of an empty list.
                    editing = ActionEditorTarget(bundleID: id, index: nil, action: nil)
                }
            }
        }
        .sheet(item: $editing) { target in
            ActionEditorSheet(target: target) { saved in
                editing = nil
                guard let saved = saved else { return }
                applyEdit(target: target, action: saved)
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
                        Text("No apps configured.\nTap + to bind actions to an app.")
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
        let count = prefs.actions(forBundleID: id).count
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
                Text("\(count)")
                    .monospacedDigit()
                    .font(.caption)
                    .foregroundStyle(.secondary)
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

    // MARK: - Action list (right column)

    private var actionList: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let id = selectedBundleID {
                actionHeader(for: id)
                Divider()
                ScrollView {
                    LazyVStack(spacing: 4) {
                        let actions = prefs.actions(forBundleID: id)
                        ForEach(Array(actions.enumerated()), id: \.element.id) { idx, action in
                            actionRow(bundleID: id, index: idx, action: action)
                        }
                        if actions.isEmpty {
                            Text("No actions yet. Tap + Add action to bind your first.")
                                .foregroundStyle(.secondary)
                                .padding(.top, 32)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                    .padding(.vertical, 8)
                    .padding(.horizontal, 12)
                }
                Divider()
                Button {
                    editing = ActionEditorTarget(bundleID: id, index: nil, action: nil)
                } label: {
                    Label("Add action…", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
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

    private func actionHeader(for id: String) -> some View {
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
            .help("Remove this app's actions")
            .buttonStyle(.borderless)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private func actionRow(bundleID: String, index: Int, action: HaloAction) -> some View {
        HStack(spacing: 10) {
            Image(systemName: action.effectiveSFSymbol)
                .frame(width: 22, height: 22)
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(action.label)
                    .font(.system(size: 13, weight: .semibold))
                Text(payloadPreview(action))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer()
            Text(slotKeyHint(forIndex: index))
                .font(.system(.caption2, design: .monospaced))
                .foregroundStyle(.tertiary)
                .frame(width: 22)
            Menu {
                Button("Edit…") {
                    editing = ActionEditorTarget(bundleID: bundleID, index: index, action: action)
                }
                Button("Move up") {
                    moveAction(bundleID: bundleID, from: index, to: index - 1)
                }
                .disabled(index == 0)
                Button("Move down") {
                    moveAction(bundleID: bundleID, from: index, to: index + 1)
                }
                .disabled(index + 1 >= prefs.actions(forBundleID: bundleID).count)
                Divider()
                Button("Delete", role: .destructive) {
                    prefs.removeAction(at: index, forBundleID: bundleID)
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.secondary.opacity(0.06)))
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

    /// Mirror of `RadialView.keyGlyph(forSlot:)` so the user can preview
    /// which digit key triggers each action slot. Kept inline rather than
    /// reaching into HaloUI's fileprivate helper to avoid widening that
    /// surface for a Settings-only need.
    private func slotKeyHint(forIndex index: Int) -> String {
        let table = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "−", "="]
        return table.indices.contains(index) ? table[index] : ""
    }

    private func moveAction(bundleID: String, from: Int, to: Int) {
        var arr = prefs.actions(forBundleID: bundleID)
        guard arr.indices.contains(from), to >= 0, to < arr.count else { return }
        let item = arr.remove(at: from)
        arr.insert(item, at: to)
        prefs.setActions(arr, forBundleID: bundleID)
    }

    private func applyEdit(target: ActionEditorTarget, action: HaloAction) {
        var arr = prefs.actions(forBundleID: target.bundleID)
        if let idx = target.index, arr.indices.contains(idx) {
            arr[idx] = action
        } else {
            arr.append(action)
        }
        prefs.setActions(arr, forBundleID: target.bundleID)
    }
}

/// Identifies which row the Action Editor sheet is targeting. `index` /
/// `action` are nil when adding a new entry.
struct ActionEditorTarget: Identifiable {
    let id = UUID()
    let bundleID: String
    let index: Int?
    let action: HaloAction?
}

/// Add / edit a single `HaloAction`. Kind picker swaps the payload field's
/// placeholder + helper text but keeps the same TextField storage so the
/// user doesn't lose their typing when switching kinds mid-edit.
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
        let existing = target.action
        _label = State(initialValue: existing?.label ?? "")
        _kind = State(initialValue: existing?.kind ?? .openFolder)
        _payload = State(initialValue: existing?.payload ?? "")
        _symbol = State(initialValue: existing?.sfSymbol ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(target.action == nil ? "Add action" : "Edit action")
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
                Button(target.action == nil ? "Add" : "Save") {
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
            id: target.action?.id ?? UUID(),
            label: label.trimmingCharacters(in: .whitespacesAndNewlines),
            kind: kind,
            payload: payload.trimmingCharacters(in: .whitespacesAndNewlines),
            sfSymbol: symbol.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : symbol
        )
    }
}
