import SwiftUI
import HaloCore

/// Action Arc — 4 chips fanning outside a single app slot. Drawn on top of
/// the existing `RadialView` (which keeps its 8 slot icons visible
/// underneath, so the user retains spatial reference).
///
/// Geometry mirrors `mockups/halo-action-arc.html` so the lived experience
/// matches the design we agreed on.
public struct ActionArcView: View {
    public let arc: ActiveArc
    public let hoverChip: Int?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Geometry mirrors `ActionArcGeometry` so render and hit-test stay
    /// in lockstep — touching one constant in `ActionArcGeometry`
    /// updates both.
    private var arcRadius: CGFloat { ActionArcGeometry.arcRadius }
    private var arcSpanDegrees: Double { ActionArcGeometry.arcSpanDegrees }
    private var chipDiameter: CGFloat { ActionArcGeometry.chipDiameter }

    public init(arc: ActiveArc, hoverChip: Int?) {
        self.arc = arc
        self.hoverChip = hoverChip
    }

    public var body: some View {
        ZStack {
            tether
            ForEach(0..<arc.chips.count, id: \.self) { idx in
                chipView(at: idx)
            }
        }
        .frame(width: HaloUI.Geometry.totalDiameter,
               height: HaloUI.Geometry.totalDiameter)
        .allowsHitTesting(false)
    }

    // MARK: - Tether

    /// Short virtual line of light from slot centre to mid-arc — anchors
    /// "this arc belongs to this slot". Done as a dashed stroke at chip
    /// accent so it reads as one element with the chips.
    @ViewBuilder
    private var tether: some View {
        let slotAngle = slotAngleRadians
        // We draw the tether as a single short Capsule rotated to the
        // slot's bearing — way cheaper than a Path stroke and looks
        // identical at this length.
        let length: CGFloat = arcRadius - HaloUI.Geometry.iconRadius - 30
        let mid: CGFloat = (arcRadius + HaloUI.Geometry.iconRadius) / 2
        let mx = cos(slotAngle) * mid
        let my = -sin(slotAngle) * mid  // SwiftUI y-down convention

        Capsule()
            .fill(Color.white.opacity(0.18))
            .frame(width: length, height: 1)
            .rotationEffect(.radians(-slotAngle))
            .offset(x: mx, y: my)
            .blur(radius: 0.4)
    }

    // MARK: - Chip

    private func chipView(at idx: Int) -> some View {
        let chip = arc.chips[idx]
        let isHovered = hoverChip == idx
        let accent = chipAccent(for: chip)
        let position = chipPosition(at: idx)
        let gated = isGated(chip)

        let glyph = glyphFor(chip)
        let label = labelFor(chip)

        return ZStack {
            // Glass base
            Circle()
                .fill(gated ? Color.black.opacity(0.45) : Color.black.opacity(0.65))
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .opacity(0.92)
                )
                .overlay(
                    Circle().strokeBorder(
                        isHovered ? accent : Color.white.opacity(0.10),
                        lineWidth: isHovered ? 1.6 : 0.8
                    )
                )
                .shadow(color: .black.opacity(0.55), radius: 9, x: 0, y: 4)
                .shadow(
                    color: isHovered && !gated ? accent.opacity(0.55) : .clear,
                    radius: 18
                )
                .frame(width: chipDiameter, height: chipDiameter)

            // Glyph
            Image(systemName: glyph)
                .font(.system(size: 17, weight: isHovered ? .semibold : .regular))
                .foregroundStyle(glyphColor(chip: chip, isHovered: isHovered, gated: gated, accent: accent))
                .scaleEffect(isHovered && !gated ? 1.10 : 1.0)

            // AX needed indicator (top-right yellow dot)
            if chip.needsAX, !arc.axGranted {
                Circle()
                    .fill(Color(red: 0.97, green: 0.71, blue: 0))
                    .overlay(Circle().strokeBorder(Color.black.opacity(0.6), lineWidth: 1))
                    .frame(width: 7, height: 7)
                    .offset(x: chipDiameter * 0.30, y: -chipDiameter * 0.30)
            }

            // Label, always on (per design — no hover-reveal)
            Text(label)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(
                    isHovered ? Color.white : Color.white.opacity(0.75)
                )
                .shadow(color: .black.opacity(0.7), radius: 1.6, x: 0, y: 0.5)
                .fixedSize()
                .offset(y: chipDiameter / 2 + 11)
        }
        .scaleEffect(isHovered && !gated ? 1.06 : 1.0)
        .offset(x: position.x, y: position.y)
        .modifier(ChipEntryAnimation(
            delay: reduceMotion ? 0 : Double(idx) * 0.030
        ))
    }

    // MARK: - Geometry

    /// Slot bearing in math convention (12 o'clock = π/2, advancing clockwise).
    /// Mirrors `RadialGeometry.center(of:sectorCount:radius:)` so chip
    /// placement is geometrically identical to the slot it fans out from.
    private var slotAngleRadians: Double {
        let n = AppPreferences.shared.slotCount
        let slice = 2 * .pi / Double(max(n, 1))
        return .pi / 2 - Double(arc.slotIndex) * slice
    }

    private var slotOrigin: CGPoint {
        let r = HaloUI.Geometry.iconRadius
        return CGPoint(
            x: cos(slotAngleRadians) * r,
            y: -sin(slotAngleRadians) * r
        )
    }

    private func chipPosition(at idx: Int) -> CGPoint {
        let spanRad = arcSpanDegrees * .pi / 180
        let count = arc.chips.count
        let step = spanRad / Double(max(count - 1, 1))
        let start = slotAngleRadians + spanRad / 2  // arc fans clockwise-of-slot first
        let a = start - step * Double(idx)
        return CGPoint(
            x: cos(a) * arcRadius,
            y: -sin(a) * arcRadius
        )
    }

    // MARK: - Style helpers

    private func chipAccent(for chip: ArcChip) -> Color {
        switch chip {
        case .builtin(.quit):              return Color(red: 1.0, green: 0.27, blue: 0.23)   // red
        case .builtin(.fullscreenToggle):  return Color(red: 0.97, green: 0.71, blue: 0)     // yellow
        case .builtin(.hide):              return Color(red: 0.23, green: 0.51, blue: 0.96)  // blue
        case .custom:                      return Color(red: 0.11, green: 0.73, blue: 0.33)  // green
        case .emptyCustom:                 return Color.white.opacity(0.40)
        }
    }

    private func isGated(_ chip: ArcChip) -> Bool {
        chip.needsAX && !arc.axGranted
    }

    private func glyphColor(chip: ArcChip, isHovered: Bool, gated: Bool, accent: Color) -> Color {
        if gated { return Color.white.opacity(0.30) }
        return isHovered ? accent : accent.opacity(0.85)
    }

    private func glyphFor(_ chip: ArcChip) -> String {
        switch chip {
        case .builtin(let kind):
            if kind == .fullscreenToggle, arc.appIsFullscreen {
                return kind.sfSymbolAlt
            }
            return kind.sfSymbol
        case .custom(let action):
            return action.effectiveSFSymbol
        case .emptyCustom:
            return "plus"
        }
    }

    private func labelFor(_ chip: ArcChip) -> String {
        switch chip {
        case .builtin(let kind):
            return arc.appIsFullscreen && kind == .fullscreenToggle
                ? kind.displayLabelAlt
                : kind.displayLabel
        case .custom(let action):
            return action.label
        case .emptyCustom:
            return NSLocalizedString("Add", comment: "Empty arc custom chip label")
        }
    }
}

private extension ArcChip {
    var needsAX: Bool {
        if case .builtin(let kind) = self { return kind.requiresAX }
        return false
    }
}

/// Sequential pop entry animation: chip fades + scales up. Stagger via the
/// `delay` so the four chips fan in one after the other. The parent owns
/// the chip's offset, so we only modulate opacity + scale here.
private struct ChipEntryAnimation: ViewModifier {
    let delay: Double
    @State private var shown = false

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .scaleEffect(shown ? 1 : 0.40)
            .onAppear {
                withAnimation(
                    .spring(response: 0.36, dampingFraction: 0.78).delay(delay)
                ) {
                    shown = true
                }
            }
    }
}
