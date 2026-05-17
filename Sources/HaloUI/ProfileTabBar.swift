import SwiftUI
import HaloCore

/// Top-strip profile switcher shown above the Halo wheel. Pill-shaped
/// segmented control inside a glass capsule — matches the handoff
/// design's "顶部 Profile 标签" variant. Hides itself when there's
/// only one profile (no point showing a degenerate single-pill
/// switcher).
///
/// Layout: rendered at the top of the panel inside the breathing-room
/// margin (`HaloUI.Geometry.totalDiameter - haloDiameter` / 2). The
/// strip is centred horizontally and sits just above the wheel's
/// outer glow.
struct ProfileTabBar: View {
    let pills: [ProfilePill]
    let activeID: UUID?
    let onSwitch: (UUID) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Single profile: no switcher to show. The Tab shortcut is
        // also a no-op in this state.
        if pills.count <= 1 {
            EmptyView()
        } else {
            HStack(spacing: 4) {
                ForEach(pills) { pill in
                    pillView(pill)
                }
            }
            .padding(4)
            .background(stripBackground)
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(strokeColor, lineWidth: 0.6)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.30 : 0.12), radius: 16, y: 6)
            .animation(Animation.Halo.echo(reduceMotion: reduceMotion), value: activeID)
        }
    }

    @ViewBuilder
    private func pillView(_ pill: ProfilePill) -> some View {
        let isActive = pill.id == activeID
        let isAll = pill.id == GridProfile.id
        let tintColor = pill.tint?.swiftUIColor ?? defaultTint
        let foreground: Color = isActive
            ? (colorScheme == .dark ? Color(white: 0.06) : Color.white)
            : (colorScheme == .dark
                ? Color.white.opacity(0.72)
                : Color.black.opacity(0.62))

        Button {
            onSwitch(pill.id)
        } label: {
            Group {
                if isAll {
                    // Built-in ALL profile renders as a 3×3 grid SF
                    // Symbol — visually distinct from named profile
                    // pills so the user reads it as a different mode.
                    Image(systemName: "circle.grid.3x3.fill")
                        .font(.system(size: 12, weight: .medium))
                } else {
                    Text(pill.name)
                        .font(.system(size: 12, weight: isActive ? .semibold : .medium))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .foregroundStyle(foreground)
            .background(
                Capsule(style: .continuous)
                    .fill(isActive ? tintColor : Color.clear)
            )
            .contentShape(Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text("Switch to \(pill.name) profile"))
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : [.isButton])
    }

    private var stripBackground: some View {
        Group {
            if #available(macOS 26.0, *) {
                Capsule(style: .continuous)
                    .fill(.clear)
                    .glassEffect(.regular, in: Capsule(style: .continuous))
            } else {
                Capsule(style: .continuous)
                    .fill(colorScheme == .dark
                        ? Color.black.opacity(0.38)
                        : Color.white.opacity(0.46))
                    .background(
                        VisualEffectBackground(
                            material: .hudWindow,
                            blendingMode: .behindWindow,
                            state: .active
                        )
                        .clipShape(Capsule(style: .continuous))
                    )
            }
        }
    }

    private var strokeColor: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.10)
            : Color.white.opacity(0.32)
    }

    /// Fallback pill tint when the profile has no user-chosen colour.
    /// Neutral light grey reads on the glass capsule without claiming
    /// an identity colour for the profile.
    private var defaultTint: Color {
        colorScheme == .dark
            ? Color.white.opacity(0.85)
            : Color.black.opacity(0.78)
    }
}
