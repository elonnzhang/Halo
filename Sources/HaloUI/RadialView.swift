import AppKit
import SwiftUI
import HaloCore

/// The radial Halo. Hue-inspired layout:
///
///   halo glow → wheel background (real NSVisualEffectView) → sectors (pie
///   slices + full-color icons) → center hub (punches donut hole, shows
///   frontmost app) → curved tooltip label floating outside the wheel.
///
/// Hover tracking uses `DragGesture(minimumDistance: 0)` instead of
/// `.onContinuousHover` — the latter doesn't fire reliably for non-key
/// windows, and Halo lives in a non-activating panel.
public struct RadialView: View {
    @ObservedObject var state: HaloState

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme

    /// Shared namespace so the wheel disc and label chip morph as one Liquid
    /// Glass system on macOS 26+. Unused on older systems but the @Namespace
    /// is cheap and keeps the codepaths symmetric.
    @Namespace private var glassNamespace

    public init(state: HaloState) {
        self.state = state
    }

    private var chrome: WheelChrome {
        WheelChrome(isDark: colorScheme == .dark)
    }

    public var body: some View {
        ZStack {
            haloGlow
            wheelBackground
            ForEach(state.slots) { slot in
                sectorView(slot: slot)
            }
            centerHub
            // Only the label sits inside a GlassEffectContainer so the chip
            // can morph between slots via `glassEffectID`. The wheel disc is
            // a single glass element on its own — no container needed — and
            // the sector icons must NOT be inside any container or they get
            // pulled into the glass sampling and frosted.
            labelOverlay
            // Action Arc (layer 2) overlays the wheel when summoned. Lives
            // on top of every slot so chips can extend past the visible
            // disc rim. The wheel itself stays visible underneath.
            if let arc = state.activeArc {
                ActionArcView(arc: arc, hoverChip: state.arcHoverChip)
            }
        }
        .frame(width: HaloUI.Geometry.totalDiameter,
               height: HaloUI.Geometry.totalDiameter)
        .scaleEffect(HaloUI.Geometry.panelScale)
        .frame(width: HaloUI.Geometry.scaledTotalDiameter,
               height: HaloUI.Geometry.scaledTotalDiameter)
        .contentShape(Circle())
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text(accessibilityRootLabel))
        .gesture(hoverGesture)
    }

    private var accessibilityRootLabel: String {
        if let arc = state.activeArc {
            return "Halo action arc for \(arc.appName)"
        }
        return "Halo radial app launcher"
    }

    @ViewBuilder
    private var labelOverlay: some View {
        // Suppress the slot label chip ONLY when the cursor is sitting on
        // the slot the arc is anchored to — that's where the chip and the
        // arc's own buttons collide, and it's also where the hub already
        // shows the anchored app's icon (so the chip is redundant).
        //
        // If the cursor moves off the anchored slot to a neighbouring app
        // while the arc is still up, that neighbour's label SHOULD show:
        // the user is now reading "what's this other app?" and the arc's
        // chips are far enough off-axis to not overlap.
        //
        // The guard is one short-circuit expression rather than a 3-branch
        // `if / else if / else` ladder. SwiftUI's `@ViewBuilder` can keep
        // a middle branch's view identity alive across an `EmptyView()`
        // swap inside a 3-branch ladder (notably under macOS 26+'s
        // `GlassEffectContainer`, where the contained `glassEffectID`
        // morph holds the capsule shape on screen even after its content
        // is gone). A single boolean guard sidesteps both issues.
        let isHoveringAnchoredSlot = state.activeArc != nil
            && state.activeArc?.slotIndex == hoveredSlot?.id
        if !isHoveringAnchoredSlot, let slot = hoveredSlot, slot.app != nil {
            if #available(macOS 26.0, *) {
                GlassEffectContainer {
                    labelChip(for: slot)
                }
            } else {
                labelChip(for: slot)
            }
        }
    }

    /// Accent colour for the halo glow + wheel tint. Returns nil when no
    /// slot is hovered (idle wheel). The arc has its own visual treatment
    /// so we don't blend its accent here.
    private var currentHoverAccent: Color? {
        hoveredSlot?.identityColor.swiftUIColor
    }

    // MARK: - Halo glow

    @ViewBuilder
    private var haloGlow: some View {
        if let accent = currentHoverAccent {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [accent.opacity(0.32), accent.opacity(0)],
                        center: .center,
                        startRadius: HaloUI.Geometry.haloDiameter / 2 - 24,
                        endRadius: HaloUI.Geometry.haloDiameter / 2 + 20
                    )
                )
                .blur(radius: 18)
                .frame(
                    width: HaloUI.Geometry.haloDiameter + 40,
                    height: HaloUI.Geometry.haloDiameter + 40
                )
                .allowsHitTesting(false)
                .transition(.opacity)
                .animation(
                    Animation.Halo.snap(reduceMotion: reduceMotion),
                    value: state.currentHoverSlot
                )
        }
    }

    // MARK: - Wheel background (liquid glass)

    private var wheelBackground: some View {
        let d = HaloUI.Geometry.haloDiameter
        let tint = currentHoverAccent ?? .clear
        let isHovering = currentHoverAccent != nil
        // Liquid Glass already produces content-aware refraction; keep the
        // manual tint subtle there. On the legacy NSVisualEffectView path the
        // material is inert, so the manual tint is the only carrier of the
        // hovered identity colour and needs to be stronger.
        let hoverTintAlpha: Double = {
            if #available(macOS 26.0, *) { return 0.06 }
            return 0.14
        }()
        return ZStack {
            // 1a. Base glass. NSVisualEffectView under a convex depth gradient
            // on macOS 14/15; native Liquid Glass on macOS 26+.
            glassDisc(diameter: d)

            // 1b. Convex depth gradient: brighter near the top-left (simulated
            // light), dimmer at the far rim so the disc reads as a polished
            // glass pebble rather than a flat black coin. Theme-aware so light
            // mode keeps the lit-from-above cue without going washed-out.
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            chrome.depthHigh,
                            chrome.depthMid,
                            chrome.depthLow,
                        ],
                        center: UnitPoint(x: 0.42, y: 0.34),
                        startRadius: 0,
                        endRadius: d / 2
                    )
                )

            // 2. Content-aware tint. Glass picks up ~5% of the hovered
            // sector's identity colour, like a prism catching a light source.
            // Masked to the donut: the hub stays neutral so the selected
            // colour reads on the ring only, not on the deadzone lens.
            Circle()
                .fill(tint.opacity(isHovering ? hoverTintAlpha : 0))
                .blendMode(.plusLighter)
                .mask(
                    Circle()
                        .fill(
                            RadialGradient(
                                stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: .clear, location: HaloUI.Geometry.deadzoneDiameter / d),
                                    .init(color: .black, location: HaloUI.Geometry.deadzoneDiameter / d),
                                    .init(color: .black, location: 1.0),
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: d / 2
                            )
                        )
                )
                .animation(
                    Animation.Halo.surface(reduceMotion: reduceMotion),
                    value: state.currentHoverSlot
                )
                .allowsHitTesting(false)

            // 3. Weight shadow at the bottom. The disc looks like it's resting
            // on something, the lower half catches less light. Kept subtle so
            // the soft-edge mask below can carry most of the rim falloff.
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Color.clear, chrome.weightShadow],
                        startPoint: UnitPoint(x: 0.5, y: 0.55),
                        endPoint: .bottom
                    )
                )
                .allowsHitTesting(false)

            // 4. Specular arc. The signature liquid-glass move: a narrow
            // bright sliver at 12 o'clock, soft blur, fading at the ends so
            // it doesn't read as a drawn stroke. (Was previously layer 5; the
            // explicit rim stroke between this and the weight gradient was
            // removed so the disc edge feathers out naturally.)
            SpecularArc(startAngleDegrees: -135, endAngleDegrees: -45)
                .stroke(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0),
                            chrome.specularBright,
                            Color.white.opacity(0)
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 1.1, lineCap: .round)
                )
                .blur(radius: 0.35)
                .padding(1.2)
                .allowsHitTesting(false)
        }
        .frame(width: d, height: d)
        .compositingGroup()
        // Soft-edge mask: opaque from center to 80 % radius, then a linear
        // alpha falloff to the rim. Was 84 %; widened to 80 % so the
        // alpha gradient slope is gentler — the previous narrow band
        // rasterized into a visible "tire-tread" stair-step (most painful
        // on dark mode, where black weight-shadow stacked on a black
        // background highlighted every alpha step).
        //
        // The matching `softEdgeStart` constant in `sectorView`'s mask
        // must stay in lockstep so sector strokes/glow fade out together
        // with the disc, not past it.
        .mask(
            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: .black, location: 0.0),
                            .init(color: .black, location: HaloUI.Geometry.softEdgeStart),
                            .init(color: .clear, location: 1.0)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: d / 2
                    )
                )
        )
        // drawingGroup forces the disc + mask + shadow chain through a
        // Metal offscreen buffer with float-precision alpha. The previous
        // direct-rasterization path was the primary source of the
        // tire-tread aliasing on the feathered rim. Skip it on Liquid
        // Glass (macOS 26+) where the system already composites this at
        // high quality and offscreen rasterization would forfeit the
        // glass's content-aware refraction.
        .modifier(LegacyAntialiased())
        // One unified soft drop. The previous double-shadow stack
        // (radius 32 + radius 8) compounded the rim alpha steps into a
        // visibly notched "tire" silhouette; one larger, slightly
        // weaker pass reads cleaner at every backdrop value.
        .shadow(color: .black.opacity(0.34), radius: 28, x: 0, y: 14)
    }

    /// Base glass disc. Liquid Glass on macOS 26+, `NSVisualEffectView`
    /// (`.hudWindow` / `.behindWindow`) elsewhere. The wheel's signature
    /// finish — depth gradient, weight shadow, rim stroke, specular arc —
    /// is rendered on top in `wheelBackground`, regardless of OS.
    @ViewBuilder
    private func glassDisc(diameter d: CGFloat) -> some View {
        if #available(macOS 26.0, *) {
            Circle()
                .fill(.clear)
                .glassEffect(in: Circle())
                .frame(width: d, height: d)
        } else {
            visualEffectDisc(diameter: d)
        }
    }

    private func visualEffectDisc(diameter d: CGFloat) -> some View {
        VisualEffectBackground(
            material: .hudWindow,
            blendingMode: .behindWindow,
            state: .active
        )
        .clipShape(Circle())
        .frame(width: d, height: d)
    }

    // MARK: - Sector

    private func sectorView(slot: HaloSlot) -> some View {
        let isHovered    = isHovered(slot.id)
        let isPreviewing = isPreviewing(slot.id)
        let isCommitting = isCommitting(slot.id)
        let isActive     = isHovered || isPreviewing
        let accent       = slot.identityColor.swiftUIColor

        // Idle sectors: completely invisible. The 1° angular gap in
        // SectorShape carries the "this disc is divided" cue on its own;
        // the previous 0.5pt idle stroke read as eight pizza-slice lines
        // overlaid on a glass pebble, fighting the Liquid Glass language.
        // Active sectors lose their hard accent stroke too — the inner
        // radial fill + blurred inner glow carry the highlight, so the
        // sector reads as "lit from within" rather than "framed".
        let idleFill = chrome.sectorIdleFill

        // Sector fill is a radial gradient: bright accent at the inner edge
        // (near the hub) bleeds outward to a subtle tint at the outer rim.
        // The inner wedge picks up the same intensity as the sector stroke,
        // giving the selected slot a "lit candle" feel.
        let innerFill: Color
        let outerFill: Color
        if isPreviewing {
            innerFill = accent.opacity(0.88)
            outerFill = accent.opacity(0.16)
        } else if isHovered {
            innerFill = accent.opacity(0.70)
            outerFill = accent.opacity(0.10)
        } else {
            innerFill = idleFill
            outerFill = idleFill
        }

        let sector = SectorShape(
            index: slot.id,
            sectorCount: state.slotCount,
            gapDegrees: HaloUI.Geometry.slotGapDegrees
        )

        return ZStack {
            sector
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: innerFill, location: 0.0),
                            .init(color: innerFill, location: 0.15),
                            .init(color: outerFill, location: 0.55),
                            .init(color: outerFill, location: 1.0),
                        ],
                        center: .center,
                        startRadius: HaloUI.Geometry.deadzoneDiameter / 2,
                        endRadius: HaloUI.Geometry.haloDiameter / 2
                    )
                )
                // Inner glow on active sectors only: a blurred accent
                // stroke masked back into the sector shape. Wider blur
                // (was radius 4) so the petal's edge dissolves into the
                // surrounding glass instead of stamping a bright wedge
                // onto it. Combined with the dropped accent stroke, the
                // active sector now reads as "lit from within", not
                // "framed and filled".
                .overlay {
                    if isActive {
                        sector
                            .stroke(accent.opacity(0.55), lineWidth: 6)
                            .blur(radius: 8)
                            .mask(sector)
                            .allowsHitTesting(false)
                    }
                }
                .frame(
                    width: HaloUI.Geometry.haloDiameter,
                    height: HaloUI.Geometry.haloDiameter
                )
                // Same soft-edge mask the disc uses, so sector fill / stroke /
                // inner glow fade out in lockstep with the visible disc rim
                // instead of punching a hard wedge into the panel's halo area.
                // Stays in lockstep with `wheelBackground`'s mask via the
                // shared `softEdgeStart` constant.
                .mask(
                    Circle()
                        .fill(
                            RadialGradient(
                                stops: [
                                    .init(color: .black, location: 0.0),
                                    .init(color: .black, location: HaloUI.Geometry.softEdgeStart),
                                    .init(color: .clear, location: 1.0),
                                ],
                                center: .center,
                                startRadius: 0,
                                endRadius: HaloUI.Geometry.haloDiameter / 2
                            )
                        )
                )

            sectorContent(slot: slot, isActive: isActive, accent: accent)
                .allowsHitTesting(false)
        }
        .scaleEffect(isCommitting ? 1.06 : 1.0)
        .animation(Animation.Halo.snap(reduceMotion: reduceMotion), value: isActive)
        .animation(Animation.Halo.snap(reduceMotion: reduceMotion), value: isCommitting)
    }

    private func sectorContent(slot: HaloSlot, isActive: Bool, accent: Color) -> some View {
        let iconCenter = RadialGeometry.center(
            of: slot.id,
            sectorCount: state.slotCount,
            radius: HaloUI.Geometry.iconRadius
        )
        // Digit-key hint (1–9 0 − =) sits on the wheel's OUTER rim — a single
        // uniform ring of labels well past the icons. Anchored to
        // `visibleOuterRadius` (where the disc's soft-edge alpha starts
        // feathering) so the labels track the rim if the user resizes the
        // wheel. Floor at iconRadius + half icon + 10 protects against
        // pathological tuning (huge icons + small wheel) collapsing the label
        // ring into the icons.
        let rimRadius = HaloUI.Geometry.visibleOuterRadius - 10
        let hintFloor = HaloUI.Geometry.iconRadius
            + HaloUI.Geometry.iconSize / 2
            + 10
        let hintRadius = max(rimRadius, hintFloor)
        let hintCenter = RadialGeometry.center(
            of: slot.id,
            sectorCount: state.slotCount,
            radius: hintRadius
        )
        // Status dot sits on an INNER ring, hub-facing side of each icon.
        // Free of the icon's top-trailing corner so the digit hint, the
        // running-status indicator, and the icon itself never share a
        // visual quadrant. Floor at hub edge + 8 keeps the dot off the
        // central hub even with aggressive tuning.
        let innerRadius = HaloUI.Geometry.iconRadius
            - HaloUI.Geometry.iconSize / 2
            - 7
        let dotFloor = HaloUI.Geometry.deadzoneDiameter / 2 + 8
        let dotRadius = max(innerRadius, dotFloor)
        let dotCenter = RadialGeometry.center(
            of: slot.id,
            sectorCount: state.slotCount,
            radius: dotRadius
        )
        // Layer-1 digit hints disappear when the Action Arc is up. The
        // digit keys are remapped to commit arc chips while the arc is
        // active, so showing slot digits would be misleading; the hints
        // also visually clashed with the arc's anchor line in early builds.
        let showKeyHint = AppPreferences.shared.numberKeyCommit && state.activeArc == nil
        let glyph = Self.keyGlyph(forSlot: slot.id)
        return ZStack {
            SlotContent(
                slot: slot,
                isActive: isActive,
                accent: accent,
                wheelHovered: state.currentHoverSlot != nil
            )
                .frame(width: HaloUI.Geometry.iconSize,
                       height: HaloUI.Geometry.iconSize)
                .offset(x: iconCenter.x, y: -iconCenter.y)

            if let dotColor = Self.statusDotColor(for: slot.runState) {
                StatusDot(color: dotColor)
                    .offset(x: dotCenter.x, y: -dotCenter.y)
            }

            if showKeyHint, let glyph {
                KeyHint(glyph: glyph, isActive: isActive, accent: accent)
                    .offset(x: hintCenter.x, y: -hintCenter.y)
            }
        }
    }

    /// Returns the dot tint for a slot's run-state, or `nil` for states that
    /// shouldn't render a dot (empty / launchable / launching).
    fileprivate static func statusDotColor(for runState: HaloSlot.RunState) -> Color? {
        switch runState {
        case .running: return Color(red: 0.11, green: 0.73, blue: 0.33)
        case .failed:  return Color(red: 1.00, green: 0.27, blue: 0.23)
        case .empty, .launchable, .launching: return nil
        }
    }

    /// Map slot index → printable key glyph the user can press to commit
    /// that slot. Mirrors the keyCode table in `AppDelegate.installKeyMonitor`
    /// (1–9, 0, `-`, `=`). Returns `nil` for slots beyond the 12-key range.
    fileprivate static func keyGlyph(forSlot index: Int) -> String? {
        let table = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "−", "="]
        return table.indices.contains(index) ? table[index] : nil
    }

    // MARK: - Center hub (recessed lens)

    private var centerHub: some View {
        let d = HaloUI.Geometry.deadzoneDiameter
        return ZStack {
            // Recessed base. Darker than the outer glass so the hub reads as
            // a depression, not a raised button.
            Circle()
                .fill(chrome.hubFill)

            // Inner shadow at the top edge. Fakes the "looking down into a
            // hole" effect: a dark, blurred stroke whose gradient is opaque
            // at 12 o'clock and clear by 6 o'clock, bleeding inward via the
            // blur so the upper interior reads as recessed.
            Circle()
                .stroke(
                    LinearGradient(
                        colors: [
                            chrome.hubInnerShadow,
                            Color.clear
                        ],
                        startPoint: .top,
                        endPoint: .center
                    ),
                    lineWidth: 3
                )
                .blur(radius: 2.6)
                .allowsHitTesting(false)

            // Lens rim. Hairline around the edge, brighter up top.
            Circle()
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            chrome.hubRimTop,
                            chrome.hubRimBottom,
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 0.8
                )

            // (The mini lens specular at -120°/-60° used to live here. It
            // harmonised with the disc's hard rim stroke. Now that the disc
            // edge is a feathered alpha mask the lens specular reads as a
            // stray white sliver, so the lens rim's top-bright gradient
            // carries the "light from above" cue on its own.)

            centerHubIcon
                .allowsHitTesting(false)
        }
        .frame(width: d, height: d)
        .shadow(color: .black.opacity(0.42), radius: 6, x: 0, y: 3)
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private var centerHubIcon: some View {
        let iconSide = HaloUI.Geometry.deadzoneDiameter * 0.62
        if let arc = state.activeArc {
            // Arc up: hub keeps the target app's icon visible so the user
            // stays oriented while picking a chip. No "ACTIONS" subtitle —
            // the arc itself signals "you're on layer 2".
            if let icon = AppIconResolver.icon(for: arc.bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: iconSide, height: iconSide)
                    .id("arc-hub-\(arc.bundleID)")
            }
        } else if let previewed = hoveredSlot?.app,
                  let icon = AppIconResolver.icon(for: previewed.bundleID) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: iconSide, height: iconSide)
                .transition(.opacity.combined(with: .scale(scale: 0.96)))
                .id(previewed.bundleID)
        } else if let originID = state.summonOriginBundleID,
                  let icon = AppIconResolver.icon(for: originID) {
            // Pre-summon frontmost app — "where you came from". We can't call
            // `NSWorkspace.shared.frontmostApplication` here because Halo has
            // already activated itself by the time Halo is rendering.
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: iconSide, height: iconSide)
                .id(originID)
        } else {
            Image(systemName: "circle.dotted")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(chrome.hubFallback)
        }
    }

    // MARK: - Label chip (glass capsule)

    private func labelChip(for slot: HaloSlot) -> some View {
        let center = RadialGeometry.center(
            of: slot.id,
            sectorCount: state.slotCount,
            radius: HaloUI.Geometry.labelRadius
        )
        return Text(slot.app?.name ?? "")
            .font(.system(size: 13, weight: .bold))
            .foregroundStyle(chrome.labelText)
            .lineLimit(2)
            .minimumScaleFactor(0.82)
            .multilineTextAlignment(.center)
            .truncationMode(.tail)
            // Tight legibility shadow on the text glyphs themselves (not the
            // capsule). Glass vibrancy can desaturate the foreground; the
            // shadow restores contrast without darkening the chip background.
            // Flips to white in light mode so it still bumps glyphs off the
            // light chip backdrop.
            .shadow(color: chrome.labelTextShadow, radius: 1.5, x: 0, y: 0.5)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .modifier(GlassChipBackground(namespace: glassNamespace, slotID: slot.id))
            .shadow(color: .black.opacity(0.38), radius: 10, x: 0, y: 5)
            .frame(maxWidth: HaloUI.Geometry.labelMaxWidth)
            .fixedSize(horizontal: false, vertical: true)
            .offset(x: center.x, y: -center.y)
            .transition(.opacity.combined(with: .scale(scale: 0.96)))
            .animation(Animation.Halo.echo(reduceMotion: reduceMotion), value: slot.id)
    }

    // MARK: - Phase helpers

    private var hoveredSlot: HaloSlot? {
        guard let id = state.currentHoverSlot else { return nil }
        return state.slots.first { $0.id == id }
    }

    private func isHovered(_ id: Int) -> Bool {
        if case .hovering(let i) = state.phase, i == id { return true }
        return false
    }

    private func isPreviewing(_ id: Int) -> Bool {
        if case .previewing(let i) = state.phase, i == id { return true }
        return false
    }

    private func isCommitting(_ id: Int) -> Bool {
        if case .committing(let i) = state.phase, i == id { return true }
        return false
    }

    // MARK: - Hit testing

    private var hoverGesture: some Gesture {
        // DragGesture(minimumDistance: 0) serves both hover tracking (onChanged
        // fires on every cursor update once the mouse is inside the view) and
        // click-to-commit (onEnded fires on mouse-up). A sibling
        // `.onTapGesture` gets swallowed by this drag on the mouseDown, which
        // is why menu-bar-summon → click never committed before — the tap
        // recogniser never won.
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                state.updateHover(slot: sectorIndex(at: value.location))
            }
            .onEnded { value in
                if let i = sectorIndex(at: value.location) {
                    state.phase = .previewing(i)
                    state.onCommit?()
                }
            }
    }

    private func sectorIndex(at location: CGPoint) -> Int? {
        // Same `reachDiameter` outer-radius as the global cursor timer in
        // HaloWindow. Within the panel's 100pt halo/shadow buffer the
        // cursor still counts as hovering the nearest sector, matching the
        // out-of-panel global path.
        RadialGeometry.sectorIndex(
            forGestureLocation: location,
            panelScale: HaloUI.Geometry.panelScale,
            totalDiameter: HaloUI.Geometry.totalDiameter,
            sectorCount: state.slotCount,
            innerRadius: HaloUI.Geometry.deadzoneDiameter / 2,
            outerRadius: HaloUI.Geometry.reachDiameter / 2
        )
    }
}

// MARK: - Slot content (icon / empty mark / status)

private struct SlotContent: View {
    let slot: HaloSlot
    let isActive: Bool
    let accent: Color
    /// Cursor is over the wheel (any slot). Only used to gate the empty-
    /// slot dashed-border breathing animation, which would otherwise burn
    /// CPU for no reason while Halo sits idle on screen.
    let wheelHovered: Bool

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        iconCanvas
            .scaleEffect(isActive ? 1.08 : 1.0)
            .overlay {
                if isActive {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(accent, lineWidth: 1.4)
                }
            }
            .animation(Animation.Halo.snap(reduceMotion: reduceMotion), value: isActive)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(accessibilityLabel))
            .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder
    private var iconCanvas: some View {
        if let app = slot.app {
            if let icon = AppIconResolver.icon(for: app.bundleID) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(
                        width: HaloUI.Geometry.iconSize - 6,
                        height: HaloUI.Geometry.iconSize - 6
                    )
                    .opacity(iconOpacity)
                    .overlay {
                        if slot.runState == .launching {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .controlSize(.small)
                                .scaleEffect(0.85)
                        }
                    }
            } else {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(accent)
                    .overlay {
                        Text(app.name.prefix(1).uppercased())
                            .font(.system(size: 20, weight: .semibold, design: .rounded))
                            .foregroundStyle(Color.black.opacity(0.78))
                    }
                    .frame(
                        width: HaloUI.Geometry.iconSize - 6,
                        height: HaloUI.Geometry.iconSize - 6
                    )
            }
        } else {
            // Match the on-screen size of real app icons (iconCanvas above
            // draws into `iconSize - 6`) so the dashed placeholder shares
            // the wheel's visual rhythm.
            EmptySlotMark(active: wheelHovered)
                .frame(width: HaloUI.Geometry.iconSize - 6,
                       height: HaloUI.Geometry.iconSize - 6)
        }
    }

    private var iconOpacity: Double {
        switch slot.runState {
        case .launchable, .launching: return 0.62
        case .failed:                 return 0.55
        default:                      return 1.0
        }
    }

    private var accessibilityLabel: String {
        if let app = slot.app { return "Switch to \(app.name)" }
        return "Empty slot — tap to pin an app"
    }
}

/// Radial key-press hint sitting on the wheel's outer rim — one uniform
/// ring of labels orbiting just inside the disc's feathered edge. Pure
/// typography (no chip, no border) so it blends with Halo's Liquid Glass
/// language and never competes with the green running-status dot at the
/// icon's top-trailing corner.
///
/// - Idle: quiet white at low opacity, no shadow. The rim glass is already
///   dark enough for white text to sit cleanly without legibility crutches.
/// - Active (hovering / previewing the slot): full white with a soft
///   accent-coloured glow, so the highlighted shortcut announces itself
///   from peripheral vision while the other eleven stay quiet.
private struct KeyHint: View {
    let glyph: String
    let isActive: Bool
    let accent: Color

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let chrome = WheelChrome(isDark: colorScheme == .dark)
        return Text(glyph)
            .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
            .tracking(0.3)
            .foregroundStyle(isActive ? chrome.keyHintActive : chrome.keyHintIdle)
            // Subtle accent halo on the active slot only. Idle digits stay
            // flat — the rim glass behind them is dark enough that any
            // shadow reads as crud instead of polish.
            .shadow(
                color: isActive ? accent.opacity(0.75) : .clear,
                radius: 5
            )
            .scaleEffect(isActive ? 1.18 : 1.0)
            .animation(Animation.Halo.snap(reduceMotion: reduceMotion), value: isActive)
            .allowsHitTesting(false)
    }
}


private struct StatusDot: View {
    let color: Color
    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay {
                Circle().stroke(Color.black.opacity(0.55), lineWidth: 0.6)
            }
    }
}

private struct EmptySlotMark: View {
    /// True while the wheel is being hovered. The dashed-border / glyph
    /// breathing animation only runs in this state — when Halo is idle on
    /// screen the placeholder stays fully static, so we don't drive a
    /// `repeatForever` animation per empty slot for nothing.
    let active: Bool

    @State private var animating = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// macOS app icons follow a squircle with ~22 % corner radius. For our
    /// 42 pt drawn-icon footprint that's ~9 pt; rounding to 11 keeps it in
    /// step with the `RoundedRectangle(cornerRadius: 11)` fallback used by
    /// `iconCanvas` for apps whose icon failed to resolve.
    private let cornerRadius: CGFloat = 11

    var body: some View {
        let chrome = WheelChrome(isDark: colorScheme == .dark)
        return ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(
                    animating ? chrome.emptyMarkStrokeActive : chrome.emptyMarkStroke,
                    style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                )
            Text("+")
                .font(.system(size: 20, weight: .light, design: .rounded))
                .foregroundStyle(animating ? chrome.emptyMarkTextActive : chrome.emptyMarkText)
        }
        .onAppear { syncBreathing(to: active) }
        .onChange(of: active) { newValue in syncBreathing(to: newValue) }
    }

    private func syncBreathing(to shouldBreathe: Bool) {
        guard !reduceMotion else {
            // Reduce Motion: never animate. Show the brighter "active"
            // state while the wheel is hovered as a static cue.
            animating = shouldBreathe
            return
        }
        if shouldBreathe {
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                animating = true
            }
        } else {
            // A short non-repeating ease-out lets the dashed border settle
            // back to idle without snapping mid-cycle.
            withAnimation(.easeOut(duration: 0.20)) {
                animating = false
            }
        }
    }
}

// MARK: - Theme-aware chrome palette

/// All the chrome colors the wheel mixes per layer — specular, depth
/// gradient, weight shadow, hub recess, sector strokes, hint glyphs, etc.
/// Picks one ramp for `colorScheme == .dark` and a softened inverted ramp
/// for light mode so the same compositional intent (lit-from-above glass
/// pebble with a recessed lens) reads correctly against either appearance.
struct WheelChrome {
    let isDark: Bool

    // Disc depth ramp — radial gradient from upper-left bright to far-rim dim.
    var depthHigh: Color { isDark ? .white.opacity(0.09) : .white.opacity(0.65) }
    var depthMid:  Color { isDark ? .white.opacity(0.02) : .white.opacity(0.18) }
    var depthLow:  Color { isDark ? .black.opacity(0.22) : .black.opacity(0.06) }

    // Bottom weight shadow, picks up "gravity" on the disc.
    var weightShadow: Color { .black.opacity(isDark ? 0.10 : 0.05) }

    // Specular arc at the top. Pure white in both modes — it's a literal
    // light-catching highlight; only the alpha tones down for light.
    // Dark mode bumped 0.78 → 0.88 so the 12-o'clock highlight reads
    // through the weight-shadow on OLED backdrops; light mode unchanged
    // (it was already plenty bright on a near-white pebble).
    var specularBright: Color { isDark ? .white.opacity(0.88) : .white.opacity(0.92) }

    // Centre hub recess. The hub is meant to read as a depression in the
    // glass, not a hole punched through it. Both modes were sitting at
    // values that made the hub read as a "well" (light) or "black hole"
    // (dark) against the surrounding glass; softened both so the lens
    // rim + inner shadow carry the recess cue instead of fill contrast.
    var hubFill: Color { isDark ? .black.opacity(0.32) : .black.opacity(0.10) }
    var hubInnerShadow: Color { isDark ? .black.opacity(0.40) : .black.opacity(0.22) }
    var hubRimTop: Color { isDark ? .white.opacity(0.24) : .black.opacity(0.18) }
    var hubRimBottom: Color { isDark ? .white.opacity(0.06) : .black.opacity(0.04) }

    // Sector chrome. Idle strokes pick up the opposite of the disc so they
    // read as "barely visible separators" without flipping the visual logic.
    var sectorIdleFill:   Color { isDark ? .white.opacity(0.015) : .black.opacity(0.012) }
    var sectorIdleStroke: Color { isDark ? .white.opacity(0.03)  : .black.opacity(0.06) }

    // Label chip text + its tight legibility shadow.
    var labelText:       Color { .primary }
    var labelTextShadow: Color { isDark ? .black.opacity(0.55) : .white.opacity(0.85) }

    // Empty-slot dashed placeholder.
    var emptyMarkStroke: Color { .primary.opacity(isDark ? 0.18 : 0.32) }
    var emptyMarkStrokeActive: Color { .primary.opacity(isDark ? 0.30 : 0.50) }
    var emptyMarkText:   Color { .primary.opacity(isDark ? 0.35 : 0.45) }
    var emptyMarkTextActive: Color { .primary.opacity(isDark ? 0.55 : 0.70) }

    // Outer-ring digit-key hint glyph.
    var keyHintIdle:   Color { .primary.opacity(isDark ? 0.38 : 0.45) }
    var keyHintActive: Color { .primary }

    // Centre-hub idle fallback glyph (`circle.dotted`).
    var hubFallback: Color { .primary.opacity(isDark ? 0.40 : 0.50) }
}

// MARK: - Antialiasing helper

/// Forces the wheel disc through an offscreen Metal buffer with float-
/// precision alpha — kills the rim stair-stepping that direct
/// rasterization produces on the soft-edge mask.
///
/// Skipped on macOS 26+ where Liquid Glass already composites at high
/// quality and the offscreen pass would forfeit the glass's content-aware
/// refraction (it can no longer sample what's behind it).
private struct LegacyAntialiased: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
        } else {
            content.drawingGroup()
        }
    }
}

// MARK: - Glass chip background

/// Capsule background for the floating label chip. macOS 26+ uses
/// `glassEffect` + `glassEffectID` so the chip morphs between slots inside
/// the shared `GlassEffectContainer`. Older systems fall back to the manual
/// `VisualEffectBackground` + capsule rim composition.
private struct GlassChipBackground: ViewModifier {
    let namespace: Namespace.ID
    let slotID: Int

    @Environment(\.colorScheme) private var colorScheme

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *) {
            content
                .glassEffect(.regular, in: Capsule(style: .continuous))
                .glassEffectID("halo.label.\(slotID)", in: namespace)
        } else {
            legacyChip(content)
        }
    }

    @ViewBuilder
    private func legacyChip(_ content: Content) -> some View {
        let isDark = colorScheme == .dark
        // White-on-glass works in dark; in light a black tint reads better
        // since the chip is sampling a brighter underlying disc.
        let tintFill: Color = isDark ? .white.opacity(0.06) : .black.opacity(0.05)
        let rimTop:   Color = isDark ? .white.opacity(0.28) : .black.opacity(0.20)
        let rimBot:   Color = isDark ? .white.opacity(0.04) : .black.opacity(0.04)
        content.background {
            Capsule(style: .continuous)
                .fill(tintFill)
                .background(
                    VisualEffectBackground(
                        material: .hudWindow,
                        blendingMode: .behindWindow,
                        state: .active
                    )
                    .clipShape(Capsule(style: .continuous))
                )
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(
                            LinearGradient(
                                colors: [rimTop, rimBot],
                                startPoint: .top,
                                endPoint: .bottom
                            ),
                            lineWidth: 0.6
                        )
                }
        }
    }
}
