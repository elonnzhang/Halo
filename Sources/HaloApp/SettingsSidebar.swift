import SwiftUI
import HaloCore

/// Top-level navigation in the v1.1 Settings panel. Four sections, three
/// content + an About footer separated by a divider — mirrors macOS Tahoe
/// System Settings rather than a plain TabView.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case apps
    case whitelist
    case actions
    case about

    var id: String { rawValue }

    var localizedTitle: String {
        switch self {
        case .general:   return NSLocalizedString("General", comment: "Settings sidebar label")
        case .apps:      return NSLocalizedString("Apps", comment: "Settings sidebar label")
        case .whitelist: return NSLocalizedString("Whitelist", comment: "Settings sidebar label")
        case .actions:   return NSLocalizedString("Actions", comment: "Settings sidebar label")
        case .about:     return NSLocalizedString("About", comment: "Settings sidebar label")
        }
    }

    var systemImage: String {
        switch self {
        case .general:   return "gearshape.fill"
        case .apps:      return "square.grid.2x2.fill"
        case .whitelist: return "shield.fill"
        case .actions:   return "bolt.fill"
        case .about:     return "info.circle.fill"
        }
    }

    var subtitle: String {
        switch self {
        case .general: return NSLocalizedString("Summon, triggers, and appearance", comment: "Settings page subtitle")
        case .apps: return NSLocalizedString("Profiles, slots, and app bindings", comment: "Settings page subtitle")
        case .whitelist: return NSLocalizedString("Keep Halo out of selected apps", comment: "Settings page subtitle")
        case .actions: return NSLocalizedString("Customize Action Arc chips", comment: "Settings page subtitle")
        case .about: return NSLocalizedString("Version, diagnostics, and links", comment: "Settings page subtitle")
        }
    }

}

enum GeneralSettingsPane: String, CaseIterable, Identifiable {
    case controls, appearance, system
    var id: String { rawValue }
    var title: String {
        switch self {
        case .controls: return NSLocalizedString("Controls", comment: "General settings group")
        case .appearance: return NSLocalizedString("Appearance", comment: "General settings group")
        case .system: return NSLocalizedString("System settings", comment: "General settings group")
        }
    }
}

struct SettingsSidebar: View {
    @Binding var selection: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            sidebarList
            Text("Halo v\(Halo.version)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
        // Native traffic lights sit over the full-size content view. Keep
        // navigation beneath them; the background remains a drag surface.
        .padding(.top, 34)
        .frame(width: 200, alignment: .leading)
        .background(sidebarBackground)
    }

    private var navigationList: some View {
        List(selection: Binding<SettingsSection?>(
            get: { selection },
            set: { if let section = $0 { selection = section } }
        )) {
            Section {
                ForEach([SettingsSection.general, .apps, .whitelist, .actions]) { section in
                    row(section)
                }
            }
            Section { row(.about) }
        }
        .listStyle(.sidebar)
    }

    @ViewBuilder
    private var sidebarList: some View {
        if #available(macOS 13.0, *) {
            navigationList.scrollContentBackground(.hidden)
        } else {
            navigationList
        }
    }

    @ViewBuilder
    private var sidebarBackground: some View {
        if #available(macOS 13.0, *) {
            Rectangle().fill(.regularMaterial)
        } else {
            Color(NSColor.windowBackgroundColor).opacity(0.7)
        }
    }

    @ViewBuilder
    private func row(_ section: SettingsSection) -> some View {
        Label(section.localizedTitle, systemImage: section.systemImage)
            .font(.system(size: 13, weight: .medium))
            .padding(.vertical, 5)
            .tag(section)
            .accessibilityHint(Text(section.subtitle))
    }
}
