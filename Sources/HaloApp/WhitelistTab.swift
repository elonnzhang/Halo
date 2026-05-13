import AppKit
import SwiftUI
import HaloCore
import HaloUI

/// Whitelist tab in the v1.1 sidebar settings panel. Manages the set of
/// frontmost apps where Halo's chord + double-tap triggers are suppressed.
/// Orthogonal to Apps tab pins — `AppPreferences.whitelistedBundleIDs`
/// has its own storage key.
struct WhitelistTab: View {
    @ObservedObject var prefs: AppPreferences

    @State private var selectedBundleID: String?
    @State private var pickerVisible = false
    @State private var confirmingRecommendedReplace = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header
            banner
            listContainer
            footerBar
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .sheet(isPresented: $pickerVisible) {
            AppPickerSheet { picked in
                pickerVisible = false
                guard let bid = picked else { return }
                var updated = prefs.whitelistedBundleIDs
                if !updated.contains(bid) { updated.append(bid) }
                prefs.whitelistedBundleIDs = updated
                selectedBundleID = bid
            }
        }
        .alert("Replace whitelist with recommended apps?", isPresented: $confirmingRecommendedReplace) {
            Button("Cancel", role: .cancel) {}
            Button("Replace", role: .destructive) {
                prefs.whitelistedBundleIDs = WhitelistSuggestions.installedSubset()
                selectedBundleID = nil
            }
        } message: {
            Text("Your current list will be replaced with installed apps from Halo's recommended set (IDEs, design tools, 3D engines, remote desktop).")
        }
    }

    @ViewBuilder
    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Whitelist").font(.system(size: 20, weight: .semibold))
            Spacer()
            Text("halo.prefs.whitelist.v1")
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var banner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .foregroundStyle(.tint)
            VStack(alignment: .leading, spacing: 2) {
                Text("Halo won't summon while these apps are frontmost.")
                    .font(.system(size: 13, weight: .medium))
                Text("Best for IDEs, games, remote desktop, design tools — anywhere ⌥ chords matter.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    @ViewBuilder
    private var listContainer: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
            if prefs.whitelistedBundleIDs.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(prefs.whitelistedBundleIDs, id: \.self) { id in
                            row(id)
                        }
                    }
                }
            }
        }
        .frame(minHeight: 280, maxHeight: .infinity)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer(minLength: 0)
            Image(systemName: "shield")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("Whitelist is empty.")
                .font(.system(size: 13, weight: .medium))
            Text("Halo will summon in every app. Add one above, or apply the recommended set below.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            Button("Apply recommended") {
                confirmingRecommendedReplace = true
            }
            .buttonStyle(.borderedProminent)
            Spacer(minLength: 0)
        }
        .padding(24)
    }

    @ViewBuilder
    private func row(_ bundleID: String) -> some View {
        let isSelected = bundleID == selectedBundleID
        Button {
            selectedBundleID = bundleID
        } label: {
            HStack(spacing: 10) {
                if let icon = AppIconResolver.icon(for: bundleID) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 22, height: 22)
                        .cornerRadius(5)
                } else {
                    RoundedRectangle(cornerRadius: 5)
                        .fill(Color.primary.opacity(0.10))
                        .frame(width: 22, height: 22)
                }
                Text(displayName(for: bundleID))
                    .font(.system(size: 13))
                    .foregroundStyle(isSelected ? Color.white : Color.primary)
                Spacer()
                Text(bundleID)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(isSelected ? Color.white.opacity(0.7) : Color.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.accentColor : Color.clear)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 0.5)
        }
    }

    @ViewBuilder
    private var footerBar: some View {
        HStack(spacing: 6) {
            Button {
                pickerVisible = true
            } label: { Image(systemName: "plus") }
            .buttonStyle(.bordered)
            .help("Add app")

            Button {
                guard let id = selectedBundleID else { return }
                prefs.whitelistedBundleIDs = prefs.whitelistedBundleIDs.filter { $0 != id }
                selectedBundleID = nil
            } label: { Image(systemName: "minus") }
            .buttonStyle(.bordered)
            .disabled(selectedBundleID == nil)
            .help("Remove selected")

            Spacer()
            Button("Apply recommended") {
                confirmingRecommendedReplace = true
            }

            Text("\(prefs.whitelistedBundleIDs.count) apps")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
        }
    }

    private func displayName(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        else { return bundleID }
        return (url.lastPathComponent as NSString).deletingPathExtension
    }
}
