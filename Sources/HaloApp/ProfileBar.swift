import SwiftUI
import AppKit
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

    var body: some View {
        HStack(spacing: 6) {
            ForEach(prefs.profiles, id: \.id) { profile in
                pill(profile)
            }
            addButton
            Spacer(minLength: 8)
            Text(metaText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 2)
        .padding(.bottom, 10)
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

    // MARK: - Pill

    @ViewBuilder
    private func pill(_ profile: BindingProfile) -> some View {
        let isActive = profile.id == prefs.activeProfileID
        let isRenaming = renamingID == profile.id

        Group {
            if isRenaming {
                renameField(for: profile)
            } else {
                Text(profile.name)
                    .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                    .lineLimit(1)
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                    // Double-click first so SwiftUI gives it priority; single
                    // click then handles plain switching.
                    .onTapGesture(count: 2) { startRename(profile) }
                    .onTapGesture(count: 1) {
                        if !isActive { prefs.switchToProfile(profile.id) }
                    }
            }
        }
        .background(pillBackground(isActive: isActive, isRenaming: isRenaming))
        .overlay(pillBorder(isActive: isActive, isRenaming: isRenaming))
        .contextMenu { pillMenu(profile, isActive: isActive) }
        .help(isActive ? "Active profile · double-click to rename"
                       : "Click to switch · double-click to rename")
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
                renameFieldFocused = true
                // Select the existing name so the user can type to
                // replace it (Finder-style rename UX).
                DispatchQueue.main.async {
                    NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
                }
            }
            .onSubmit { commitRename(for: profile.id) }
            .onExitCommand { cancelRename() }
    }

    @ViewBuilder
    private func pillBackground(isActive: Bool, isRenaming: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        if isRenaming {
            shape.fill(Color(nsColor: .textBackgroundColor))
        } else if isActive {
            shape
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.06), radius: 1, x: 0, y: 1)
        } else {
            shape.fill(Color(nsColor: .controlBackgroundColor))
        }
    }

    private func pillBorder(isActive: Bool, isRenaming: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 7, style: .continuous)
        let color: Color
        let width: CGFloat
        if isRenaming {
            color = Color.accentColor
            width = 1.5
        } else if isActive {
            color = Color.accentColor.opacity(0.55)
            width = 0.5
        } else {
            color = Color.primary.opacity(0.10)
            width = 0.5
        }
        return shape.strokeBorder(color, lineWidth: width)
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
