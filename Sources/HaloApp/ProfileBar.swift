import SwiftUI
import AppKit
import UniformTypeIdentifiers
import HaloCore
import HaloUI

/// Scene switcher at the top of `AppsTab`. Every profile is a chip in a
/// wrapping row, so all of them stay visible and reachable without hidden
/// scrolling however many there are. Switching, renaming, duplicating,
/// deleting and drag-to-reorder all flow through here, beside the
/// "Show ALL" switch and the manage menu.
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
    @State private var dropTargetID: UUID?

    /// Fallback color palette used when a profile has no `tint` set.
    /// Six OKLCH-tuned hues at perceptually-matched lightness/chroma —
    /// distinguishable at 8pt without being garish. Index into by
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
        VStack(alignment: .leading, spacing: 10) {
            header
            FlowLayout(spacing: 8, lineSpacing: 8) {
                ForEach(Array(prefs.profiles.enumerated()), id: \.element.id) { index, profile in
                    chip(profile, index: index)
                }
                newChip
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(Text("Profiles"))
        }
        .onDisappear {
            if let id = renamingID { commitRename(for: id) }
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

    // MARK: - Header

    /// Count on the left; the ALL switch and the active profile's manage
    /// menu on the right, so both stay in view however the chips wrap.
    private var header: some View {
        HStack(spacing: 12) {
            Text(metaText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            showAllTab
            manageMenu
        }
    }

    /// "Show ALL" adds a built-in ALL pill to the launcher's profile strip,
    /// which is why the switch lives with the profile controls.
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
    }

    private var manageMenu: some View {
        Menu {
            pillMenu(prefs.activeProfile, isActive: true)
        } label: {
            // A titled icon-only label keeps "Manage profile" as the
            // accessible name; a bare symbol falls back to "More".
            Label("Manage profile", systemImage: "ellipsis")
                .labelStyle(.iconOnly)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Manage profile")
    }

    // MARK: - Chips

    @ViewBuilder
    private func chip(_ profile: BindingProfile, index: Int) -> some View {
        if renamingID == profile.id {
            renameChip(profile)
        } else {
            let isActive = profile.id == prefs.activeProfileID
            // A real button, so Full Keyboard Access can focus and press
            // the chip. The first click of a double-click selects, as in
            // Finder; the second opens rename.
            Button { select(profile) } label: {
                SceneChip(
                    name: profile.name,
                    dot: dotColor(for: profile, index: index),
                    accent: profile.tint?.swiftUIColor,
                    isActive: isActive,
                    insertion: insertionEdge(for: profile)
                )
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture(count: 2).onEnded { startRename(profile) })
            .contextMenu { pillMenu(profile, isActive: isActive) }
            .help(chipHelp(profile, isActive: isActive))
            .onDrag {
                draggedID = profile.id
                return NSItemProvider(object: profile.id.uuidString as NSString)
            }
            .onDrop(of: [UTType.plainText], delegate: ProfileChipDropDelegate(
                targetID: profile.id,
                prefs: prefs,
                draggedID: $draggedID,
                dropTargetID: $dropTargetID
            ))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(profile.name))
            .accessibilityAddTraits(isActive ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction { select(profile) }
            .accessibilityAction(named: Text("Rename…")) { startRename(profile) }
            .accessibilityAction(named: Text("Duplicate")) { duplicate(profile) }
            .accessibilityAction(named: Text("Delete")) {
                if prefs.profiles.count > 1 { deletingID = profile.id }
            }
        }
    }

    /// 8pt dot to the left of the name. Uses the profile's `tint` when
    /// set; otherwise picks from a fallback palette by row index at 60%
    /// opacity, so an unset tint reads as "not customised yet".
    private func dotColor(for profile: BindingProfile, index: Int) -> Color {
        if let tint = profile.tint { return tint.swiftUIColor }
        return Self.fallbackPalette[index % Self.fallbackPalette.count].opacity(0.6)
    }

    /// `reorderProfile` lands the dragged chip on the target's index, i.e.
    /// before it when dragging left and after it when dragging right.
    private func insertionEdge(for profile: BindingProfile) -> SceneChip.Insertion? {
        guard dropTargetID == profile.id,
              let dragged = draggedID, dragged != profile.id,
              let from = prefs.profiles.firstIndex(where: { $0.id == dragged }),
              let to = prefs.profiles.firstIndex(where: { $0.id == profile.id })
        else { return nil }
        return from > to ? .leading : .trailing
    }

    /// The name leads the tooltip because long names are truncated in the chip.
    private func chipHelp(_ profile: BindingProfile, isActive: Bool) -> String {
        let hint = isActive
            ? NSLocalizedString("Active profile · double-click to rename · drag to reorder", comment: "")
            : NSLocalizedString("Click to switch · double-click to rename · drag to reorder", comment: "")
        return "\(profile.name)\n\(hint)"
    }

    private func renameChip(_ profile: BindingProfile) -> some View {
        TextField("Name", text: $renameDraft)
            .textFieldStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .focused($renameFieldFocused)
            .padding(.horizontal, 12)
            .frame(width: 148, height: 28)
            .background(Capsule(style: .circular).fill(Color(nsColor: .textBackgroundColor)))
            .overlay(Capsule(style: .circular).strokeBorder(Color.accentColor, lineWidth: 1.5))
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
            // Clicking elsewhere keeps the typed name instead of leaving
            // the field stuck open.
            .compatOnChange(of: renameFieldFocused) { focused in
                if !focused, renamingID == profile.id { commitRename(for: profile.id) }
            }
    }

    @ViewBuilder
    private func pillMenu(_ profile: BindingProfile, isActive: Bool) -> some View {
        if !isActive {
            Button("Switch to \(profile.name)") {
                select(profile)
            }
        }
        Button("Rename…") { startRename(profile) }
        Button("Duplicate") { duplicate(profile) }
        Divider()
        Button("Delete", role: .destructive) {
            deletingID = profile.id
        }
        .disabled(prefs.profiles.count <= 1)
    }

    /// Moving to another chip mid-rename keeps what was typed.
    private func select(_ profile: BindingProfile) {
        if let id = renamingID, id != profile.id { commitRename(for: id) }
        prefs.switchToProfile(profile.id)
    }

    private func startRename(_ profile: BindingProfile) {
        if let id = renamingID, id != profile.id { commitRename(for: id) }
        renameDraft = profile.name
        renamingID = profile.id
        // onAppear in renameChip wires focus + select-all.
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

    /// The copy becomes the active profile, like a freshly created one, so
    /// the result is visible and editable straight away.
    private func duplicate(_ profile: BindingProfile) {
        let copy = prefs.addProfile(name: "\(profile.name) copy", cloning: profile.id)
        prefs.switchToProfile(copy.id)
    }

    // MARK: - New chip

    private var newChip: some View {
        Button {
            newName = defaultNewProfileName()
            newCloneActive = true
            showingNewSheet = true
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                Text("New")
                    .font(.system(size: 13, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .frame(height: 28)
            .overlay(
                Capsule(style: .circular)
                    .strokeBorder(style: StrokeStyle(lineWidth: 0.75, dash: [3, 3]))
                    .foregroundStyle(Color.primary.opacity(0.28))
            )
            .contentShape(Capsule(style: .circular))
        }
        .buttonStyle(.plain)
        .help("New profile")
        .accessibilityLabel(Text("New profile"))
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

    /// Creating a profile selects it, so it shows up as the active chip
    /// instead of silently appearing at the end of the row.
    private func createIfValid() {
        guard !trimmedNewName.isEmpty else { return }
        let created = prefs.addProfile(
            name: trimmedNewName,
            cloning: newCloneActive ? prefs.activeProfileID : nil
        )
        prefs.switchToProfile(created.id)
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

/// Drop delegate for one chip. Dropping another chip onto it calls
/// `reorderProfile` so the dragged profile lands at this chip's index, and
/// `dropTargetID` drives the insertion marker while the drag hovers here.
private struct ProfileChipDropDelegate: DropDelegate {
    let targetID: UUID
    let prefs: AppPreferences
    @Binding var draggedID: UUID?
    @Binding var dropTargetID: UUID?

    func dropEntered(info: DropInfo) {
        dropTargetID = targetID
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func dropExited(info: DropInfo) {
        if dropTargetID == targetID { dropTargetID = nil }
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggedID = nil
            dropTargetID = nil
        }
        guard let dragged = draggedID, dragged != targetID,
              let targetIndex = prefs.profiles.firstIndex(where: { $0.id == targetID })
        else { return false }
        withAnimation(.easeOut(duration: 0.18)) {
            prefs.reorderProfile(dragged, to: targetIndex)
        }
        return true
    }
}

/// One scene chip: colour dot + name in a capsule. The active chip takes
/// the scene's tint (a neutral wash when it has none), matching the hero
/// card below; the marker shows where a dragged chip will land. Capsules
/// are `.circular`: hairline strokes on `.continuous` ones render stray
/// ticks at both ends.
private struct SceneChip: View {
    enum Insertion { case leading, trailing }

    let name: String
    let dot: Color
    let accent: Color?
    let isActive: Bool
    let insertion: Insertion?

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(dot).frame(width: 8, height: 8)
            Text(name)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isActive ? Color.primary : Color.primary.opacity(0.78))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .padding(.horizontal, 12)
        .frame(height: 28)
        .frame(maxWidth: 176)
        .background(Capsule(style: .circular).fill(fill))
        .overlay(Capsule(style: .circular).strokeBorder(stroke, lineWidth: isActive ? 1 : 0.5))
        .overlay(alignment: insertion == .leading ? .leading : .trailing) { marker }
        .contentShape(Capsule(style: .circular))
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: isActive)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.10), value: hovering)
    }

    private var wash: Color { accent ?? Color.primary }

    private var fill: Color {
        if isActive { return wash.opacity(accent == nil ? 0.10 : 0.16) }
        return Color.primary.opacity(hovering ? 0.085 : 0.045)
    }

    private var stroke: Color {
        if isActive { return wash.opacity(accent == nil ? 0.32 : 0.60) }
        return Color.primary.opacity(0.10)
    }

    @ViewBuilder
    private var marker: some View {
        if let insertion {
            Capsule(style: .circular)
                .fill(Color.accentColor)
                .frame(width: 2.5, height: 22)
                .offset(x: insertion == .leading ? -5.25 : 5.25)
                .allowsHitTesting(false)
        }
    }
}
