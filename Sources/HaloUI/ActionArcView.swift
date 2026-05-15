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
    @Environment(\.colorScheme) private var colorScheme

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
            ForEach(0..<arc.chips.count, id: \.self) { idx in
                chipView(at: idx)
            }
        }
        // Remount the whole arc when re-anchoring to a different slot so
        // the chip pop-in animation replays — gives the user a visible
        // "now we're on a different app's arc" cue rather than a
        // silent swap that looks like nothing happened.
        .id("arc-\(arc.slotIndex)-\(arc.bundleID)")
        .frame(width: HaloUI.Geometry.totalDiameter,
               height: HaloUI.Geometry.totalDiameter)
        .allowsHitTesting(false)
    }

    // MARK: - Chip

    private func chipView(at idx: Int) -> some View {
        let chip = arc.chips[idx]
        let isHovered = hoverChip == idx
        let accent = chipAccent(for: chip)
        let position = chipPosition(at: idx)
        let gated = isGated(chip)
        let chrome = ArcChipChrome(isDark: colorScheme == .dark)

        let glyph = glyphFor(chip)
        let label = labelFor(chip)

        return ZStack {
            // Glass base. Fill / stroke / shadow all read from
            // ArcChipChrome so the chip matches whichever wheel
            // appearance the user is on (the wheel itself flips via
            // WheelChrome the same way).
            Circle()
                .fill(gated ? chrome.fillGated : chrome.fill)
                .background(
                    Circle()
                        .fill(.ultraThinMaterial)
                        .opacity(0.92)
                )
                .overlay(
                    Circle().strokeBorder(
                        isHovered ? accent : chrome.strokeIdle,
                        lineWidth: isHovered ? 1.6 : 0.8
                    )
                )
                .shadow(color: chrome.dropShadow, radius: 9, x: 0, y: 4)
                .shadow(
                    color: isHovered && !gated ? accent.opacity(0.55) : .clear,
                    radius: 18
                )
                .frame(width: chipDiameter, height: chipDiameter)

            // Glyph
            Image(systemName: glyph)
                .font(.system(size: 17, weight: isHovered ? .semibold : .regular))
                .foregroundStyle(glyphColor(
                    isHovered: isHovered,
                    gated: gated,
                    accent: accent,
                    chrome: chrome
                ))
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
                    isHovered ? chrome.labelActive : chrome.labelIdle
                )
                .shadow(color: chrome.labelShadow, radius: 1.6, x: 0, y: 0.5)
                .fixedSize()
                .offset(y: chipDiameter / 2 + 11)
        }
        .scaleEffect(isHovered && !gated ? 1.06 : 1.0)
        .offset(x: position.x, y: position.y)
        .modifier(ChipEntryAnimation(
            delay: reduceMotion ? 0 : Double(idx) * Animation.Halo.arcChipStagger
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

    private func glyphColor(
        isHovered: Bool,
        gated: Bool,
        accent: Color,
        chrome: ArcChipChrome
    ) -> Color {
        if gated { return chrome.glyphGated }
        if isHovered { return accent }
        return chrome.idleGlyph(accent: accent)
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

// MARK: - Theme-aware chip palette

/// Per-mode tokens for an Action Arc chip. Mirrors `WheelChrome`'s split:
/// dark mode keeps the established "black glass + tinted glyph" reading;
/// light mode flips to "translucent white glass + neutral glyph" so a
/// chip on a near-white wheel doesn't read as a foreign black puck.
///
/// Accent colours (red/yellow/blue/green) themselves don't change per
/// mode — they're identity, not chrome — but the *idle* glyph in light
/// mode goes neutral grey so a yellow Fullscreen icon stays legible on
/// white glass. Hovered chip still tints the glyph to accent in both
/// modes; that's the "this is the chip you're picking" signal.
struct ArcChipChrome {
    let isDark: Bool

    // Glass fill behind .ultraThinMaterial. Dark mode darkens the
    // material; light mode lifts it brighter than the wheel so the chip
    // reads as a separate puck and not a wheel cutout.
    var fill: Color       { isDark ? .black.opacity(0.65) : .white.opacity(0.55) }
    var fillGated: Color  { isDark ? .black.opacity(0.45) : .white.opacity(0.40) }

    // Idle 0.8pt rim. Hovered rim uses the chip's accent in both modes
    // (handled at the call site); this is just the "chip exists" hint.
    var strokeIdle: Color { isDark ? .white.opacity(0.10) : .black.opacity(0.10) }

    // Drop shadow under the chip. Light mode is much weaker — strong
    // shadow on a light backdrop reads as cartoonish, and the wheel's
    // own shadow already separates the chip from the desktop.
    var dropShadow: Color { isDark ? .black.opacity(0.55) : .black.opacity(0.20) }

    // Label text under the chip ("Quit" / "Fullscreen" / "Hide" / "Add").
    var labelIdle: Color   { isDark ? .white.opacity(0.75) : .black.opacity(0.70) }
    var labelActive: Color { isDark ? .white               : .black }
    // Tight legibility shadow on the glyphs themselves. Light mode flips
    // to a white halo so dark text still bumps off the bright disc.
    var labelShadow: Color { isDark ? .black.opacity(0.70) : .white.opacity(0.85) }

    // Idle glyph. Dark mode keeps the chip-tinted look ("warm coloured
    // glyph on cool black glass") because that look reads well at night.
    // Light mode goes neutral so accent colours like the Fullscreen
    // yellow don't dissolve into white glass.
    var glyphGated: Color { isDark ? .white.opacity(0.30) : .black.opacity(0.30) }
    func idleGlyph(accent: Color) -> Color {
        isDark ? accent.opacity(0.85) : .black.opacity(0.62)
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
                withAnimation(Animation.Halo.chipPop(delay: delay)) {
                    shown = true
                }
            }
    }
}
