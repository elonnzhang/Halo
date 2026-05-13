import SwiftUI
import HaloCore

/// Top-level navigation in the v1.1 Settings panel. Four sections, three
/// content + an About footer separated by a divider — mirrors macOS Tahoe
/// System Settings rather than a plain TabView.
enum SettingsSection: String, CaseIterable, Identifiable {
    case general
    case apps
    case whitelist
    case about

    var id: String { rawValue }

    var localizedTitle: LocalizedStringKey {
        switch self {
        case .general:   return "General"
        case .apps:      return "Apps"
        case .whitelist: return "Whitelist"
        case .about:     return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general:   return "gearshape.fill"
        case .apps:      return "square.grid.2x2.fill"
        case .whitelist: return "shield.fill"
        case .about:     return "info.circle.fill"
        }
    }

    /// Tile gradient per the mockup. Uses `LinearGradient(gradient:…)` to
    /// stay within macOS 12's API surface (the `init(colors:…)` shorthand
    /// is iOS 15 / macOS 12 too, but explicit `Gradient` reads cleanly).
    var tileGradient: LinearGradient {
        let colors: [Color]
        switch self {
        case .general:
            colors = [Color(red: 0.56, green: 0.56, blue: 0.58),
                      Color(red: 0.39, green: 0.39, blue: 0.40)]
        case .apps:
            colors = [Color(red: 0.04, green: 0.52, blue: 1.00),
                      Color(red: 0.37, green: 0.36, blue: 0.90)]
        case .whitelist:
            colors = [Color(red: 0.19, green: 0.82, blue: 0.35),
                      Color(red: 0.20, green: 0.78, blue: 0.35)]
        case .about:
            colors = [Color(red: 0.39, green: 0.82, blue: 1.00),
                      Color(red: 0.04, green: 0.52, blue: 1.00)]
        }
        return LinearGradient(
            gradient: Gradient(colors: colors),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct SettingsSidebar: View {
    @Binding var selection: SettingsSection

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach([SettingsSection.general, .apps, .whitelist], id: \.id) { section in
                row(section)
            }
            Divider().padding(.vertical, 6).padding(.horizontal, 6)
            row(.about)
            Spacer(minLength: 0)
            Text("Halo v\(Halo.version)")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .padding(.horizontal, 10)
                .padding(.bottom, 6)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 6)
        .frame(width: 200, alignment: .leading)
        .background(sidebarBackground)
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
        let isActive = selection == section
        Button {
            selection = section
        } label: {
            HStack(spacing: 9) {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(section.tileGradient)
                    Image(systemName: section.systemImage)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .frame(width: 20, height: 20)

                Text(section.localizedTitle)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isActive ? Color.white : Color.primary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isActive ? Color.accentColor : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
