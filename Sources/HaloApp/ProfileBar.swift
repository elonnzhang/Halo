import SwiftUI
import AppKit
import UniformTypeIdentifiers
import HaloCore
import HaloUI

/// Lives at the top of `AppsTab`. The *only* UI surface for the
/// initial multi-profile scope: a pill row + `+` button + meta count.
/// Switching, renaming, duplicating, deleting all flow through here.
struct ProfileBar: View {
    @ObservedObject var prefs: AppPreferences

    @State private var renamingID: UUID?
    @State private var renameDraft: String = ""
    @FocusState private var renameFieldFocused: Bool

    @State private var showingNewSheet = false
    @State private var newName: String = ""
    @State private var newCloneActive = true
    @State private var deletingID: UUID?
    @State private var draggedID: UUID?

    /// Fallback color palette used when a profile has no `tint` set.
    /// Six OKLCH-tuned hues at perceptually-matched lightness/chroma —
    /// distinguishable at 6pt without being garish. Index into by
    /// profile's row position so order is stable.
    private static let fallbackPalette: [Color] = [
        IdentityColor(lightness: 0.65, chroma: 0.18, hue: 25).swiftUIColor,   // red
        IdentityColor(lightness: 0.78, chroma: 0.16, hue: 80).swiftUIColor,   // amber
        IdentityColor(lightness: 0.70, chroma: 0.16, hue: 145).swiftUIColor,  // green
        IdentityColor(lightness: 0.68, chroma: 0.14, hue: 190).swiftUIColor,  // teal
        IdentityColor(lightness: 0.62, chroma: 0.18, hue: 250).swiftUIColor,  // blue
        IdentityColor(lightness: 0.65, chroma: 0.18, hue: 325).swiftUIColor,  // magenta
    ]

    var body: some View {
        VStack(spacing: 0) {
            SettingsTabsHeader {
                ScrollView(.horizontal, showsIndicators: false) {
                    profileTabs
                        .frame(width: max(360, CGFloat(prefs.profiles.count) * 90), height: 28)
                }
            }
            HStack(spacing: 8) {
                addButton
                Menu {
                    pillMenu(prefs.activeProfile, isActive: true)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Manage profile")
                .accessibilityLabel(Text("Manage profile"))
                showAllTab
                Spacer(minLength: 8)
                Text(metaText)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
        }
        .sheet(isPresented: $showingNewSheet) { newProfileSheet }
        .alert(
            "Delete profile?",
            isPresented: Binding(
                get: { deletingID != nil },
                set: { if !$0 { deletingID = nil } }
            )
        ) {
            Button("Cancel", role: .cancel) { deletingID = nil }
            Button("Delete", role: .destructive) {
                if let id = deletingID { prefs.deleteProfile(id) }
                deletingID = nil
            }
        } message: {
            Text("This profile's pins and identity colours will be removed. Global settings are unaffected.")
        }
    }

    /// "Show ALL" rendered as a left-aligned tab beside the scene pills.
    /// It belongs in this row because it adds a built-in ALL pill to the
    /// same switcher; keeping it next to the pills (rather than floating
    /// on the trailing edge) keeps it visible when the window narrows.
    private var showAllTab: some View {
        Toggle(isOn: Binding(
            get: { prefs.showAllProfile },
            set: { prefs.showAllProfile = $0 }
        )) {
            Text("Show ALL")
                .font(.system(size: 12, weight: .medium))
        }
        .toggleStyle(.switch)
        .controlSize(.mini)
        .fixedSize()
        .help("Adds a built-in profile that opens a watchOS-style grid of every installed app. Tab to switch to it.")
        .padding(.leading, 4)
    }

    // MARK: - Pill

    private var profileTabs: some View {
        SettingsSegmentedTabs(
            labels: prefs.profiles.map { renamingID == $0.id ? "" : "  \($0.name)" },
            selectedIndex: prefs.profiles.firstIndex(where: { $0.id == prefs.activeProfileID }) ?? 0,
            accessibilityLabel: NSLocalizedString("Profiles", comment: ""),
            onSelect: { index in
                guard prefs.profiles.indices.contains(index) else { return }
                prefs.switchToProfile(prefs.profiles[index].id)
            }
        )
        // Native control owns its appearance and keyboard/accessibility
        // selection. Transparent per-segment targets retain the existing
        // profile double-click, context menu and drag/drop interactions.
        .allowsHitTesting(false)
        .overlay {
            HStack(spacing: 0) {
                ForEach(Array(prefs.profiles.enumerated()), id: \.element.id) { index, profile in
                    pill(profile, index: index)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    @ViewBuilder
    private func pill(_ profile: BindingProfile, index: Int) -> some View {
        let isActive = profile.id == prefs.activeProfileID
        let isRenaming = renamingID == profile.id

        Group {
            if isRenaming {
                renameField(for: profile)
                    .background(Color(nsColor: .textBackgroundColor))
            } else {
                HStack {
                    colorDot(for: profile, index: index)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 10)
                .frame(height: 28)
                .contentShape(Rectangle())
                // Double-click first so SwiftUI gives it priority; single
                // click then handles plain switching.
                .onTapGesture(count: 2) { startRename(profile) }
                .onTapGesture(count: 1) {
                    if !isActive { prefs.switchToProfile(profile.id) }
                }
            }
        }
        .accessibilityHidden(!isRenaming)
        .opacity(draggedID == profile.id ? 0.45 : 1.0)
        .contextMenu { pillMenu(profile, isActive: isActive) }
        .help(isActive ? "Active profile · double-click to rename · drag to reorder"
                       : "Click to switch · double-click to rename · drag to reorder")
        .onDrag {
            draggedID = profile.id
            return NSItemProvider(object: profile.id.uuidString as NSString)
        }
        .onDrop(of: [UTType.plainText], delegate: ProfilePillDropDelegate(
            targetID: profile.id,
            prefs: prefs,
            draggedID: $draggedID
        ))
    }

    /// 6pt circle to the left of the pill label. Uses the profile's
    /// `tint` when set; otherwise picks from a fallback palette by row
    /// index. Unset tint is rendered at 60% opacity so the user can see
    /// at a glance that the slot hasn't been customised yet.
    private func colorDot(for profile: BindingProfile, index: Int) -> some View {
        let color: Color
        let opacity: Double
        if let tint = profile.tint {
            color = tint.swiftUIColor
            opacity = 1.0
        } else {
            color = Self.fallbackPalette[index % Self.fallbackPalette.count]
            opacity = 0.6
        }
        return Circle()
            .fill(color.opacity(opacity))
            .frame(width: 6, height: 6)
    }

    private func renameField(for profile: BindingProfile) -> some View {
        TextField("Name", text: $renameDraft)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .semibold))
            .focused($renameFieldFocused)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .frame(minWidth: 70, maxWidth: 160)
            .onAppear {
                // Select the existing name so the user can type to
                // replace it (Finder-style rename UX).
                DispatchQueue.main.async {
                    renameFieldFocused = true
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
            }
            .onSubmit { commitRename(for: profile.id) }
            .onExitCommand { cancelRename() }
    }

    @ViewBuilder
    private func pillMenu(_ profile: BindingProfile, isActive: Bool) -> some View {
        if !isActive {
            Button("Switch to \(profile.name)") {
                prefs.switchToProfile(profile.id)
            }
        }
        Button("Rename…") { startRename(profile) }
        Button("Duplicate") {
            _ = prefs.addProfile(name: "\(profile.name) copy", cloning: profile.id)
        }
        Divider()
        Button("Delete", role: .destructive) {
            deletingID = profile.id
        }
        .disabled(prefs.profiles.count <= 1)
    }

    private func startRename(_ profile: BindingProfile) {
        renameDraft = profile.name
        renamingID = profile.id
        // onAppear in renameField wires focus + select-all.
    }

    private func commitRename(for id: UUID) {
        let trimmed = renameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { prefs.renameProfile(id, to: trimmed) }
        renamingID = nil
        renameFieldFocused = false
    }

    private func cancelRename() {
        renamingID = nil
        renameFieldFocused = false
    }

    // MARK: - Add button

    private var addButton: some View {
        Button {
            newName = defaultNewProfileName()
            newCloneActive = true
            showingNewSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 0.5, dash: [3, 3]))
                        .foregroundStyle(Color.primary.opacity(0.25))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("New profile")
    }

    // MARK: - New profile sheet

    private var newProfileSheet: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("New profile").font(.headline)

            TextField("Name", text: $newName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(createIfValid)

            Picker("Start from", selection: $newCloneActive) {
                Text("Blank").tag(false)
                Text(String(format: NSLocalizedString("Clone of %@", comment: ""),
                            prefs.activeProfile.name))
                    .tag(true)
            }
            .pickerStyle(.segmented)

            HStack {
                Spacer()
                Button("Cancel") { showingNewSheet = false }
                Button("Create", action: createIfValid)
                    .keyboardShortcut(.defaultAction)
                    .disabled(trimmedNewName.isEmpty)
            }
        }
        .padding(18)
        .frame(width: 340)
    }

    private var trimmedNewName: String {
        newName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func createIfValid() {
        guard !trimmedNewName.isEmpty else { return }
        _ = prefs.addProfile(
            name: trimmedNewName,
            cloning: newCloneActive ? prefs.activeProfileID : nil
        )
        showingNewSheet = false
    }

    private func defaultNewProfileName() -> String {
        "Profile \(prefs.profiles.count + 1)"
    }

    private var metaText: String {
        let n = prefs.profiles.count
        let key = n == 1 ? "%d profile" : "%d profiles"
        return String(format: NSLocalizedString(key, comment: ""), n)
    }
}

/// Drop delegate for one pill. When another pill is dropped onto this
/// one, calls `reorderProfile` so the dragged profile lands at this
/// pill's current index. Restores `draggedID` once the drop resolves so
/// the source pill's opacity returns to 1.0.
private struct ProfilePillDropDelegate: DropDelegate {
    let targetID: UUID
    let prefs: AppPreferences
    @Binding var draggedID: UUID?

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        // Mouse left the pill mid-drag; nothing to do — the drag is
        // still live, so we don't reset `draggedID` until the drag
        // either commits via performDrop or is cancelled (handled by
        // the next drag start overwriting `draggedID`).
    }

    func performDrop(info: DropInfo) -> Bool {
        guard let dragged = draggedID, dragged != targetID else {
            draggedID = nil
            return false
        }
        guard let targetIndex = prefs.profiles.firstIndex(where: { $0.id == targetID }) else {
            draggedID = nil
            return false
        }
        prefs.reorderProfile(dragged, to: targetIndex)
        draggedID = nil
        return true
    }
}
