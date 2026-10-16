import AppKit
import SwiftUI
import UniformTypeIdentifiers
import HaloCore
import HaloUI

/// Visual binding editor: a miniature Halo wheel rendered inside Settings
/// → Apps. Mirrors the live Halo's geometry (`SectorShape` + the same
/// `iconRadius` formula tied to the soft-edge mask) so the user is
/// editing exactly the layout they'll see when they summon Halo.
///
/// Interaction
/// - Tap an empty slot → opens `AppPickerSheet` to pin an app.
/// - Tap a pinned slot → opens a popover with Change / Clear / colour
///   controls anchored to that slot.
/// - Drag a pinned slot onto another slot → swap the two pins (or move
///   the source pin into an empty target, leaving the source empty).
struct BindingWheelView: View {
    @ObservedObject var prefs: AppPreferences

    @State private var editingSlot: Int? = nil
    @State private var pickerForSlot: Int? = nil
    @State private var draggedSlot: Int? = nil
    @State private var hoverSlot: Int? = nil

    // Geometry tuned for the resizable Settings detail pane. Smaller than the
    // live Halo (which is 380 pt) so it doesn't dominate the panel, but
    // proportionally identical.
    private let diameter: CGFloat = 280
    private let hubDiameter: CGFloat = 78
    private let iconVisualSize: CGFloat = 38
    private let iconBoxSize: CGFloat = 52      // tappable area, larger than the icon glyph

    /// Cheap stateless extractor — same one AppDelegate uses for the live
    /// wheel. Lets the Settings preview show the same icon-derived identity
    /// colour the user will see when they summon Halo, not just overrides.
    private let extractor = DominantColorExtractor()

    /// Visible outer rim (where the soft mask starts fading) divided by
    /// half the deadzone — same logic as `HaloUI.Geometry.iconRadius`.
    private var iconRadius: CGFloat {
        let visibleOuter = diameter / 2 * 0.84
        let hubOuter = hubDiameter / 2
        return (visibleOuter + hubOuter) / 2
    }

    var body: some View {
        ZStack {
            wheelBackground
            sectors
            slotButtons
            centerHub
        }
        .frame(width: diameter + 60, height: diameter + 60)
        // Reset edit state if the user changes slot count under us.
        .compatOnChange(of: prefs.slotCount) { _ in
            editingSlot = nil
            pickerForSlot = nil
            draggedSlot = nil
            hoverSlot = nil
        }
        // Profile switch wipes drag state so a half-finished drag from
        // the old profile doesn't carry into the new one.
        .compatOnChange(of: prefs.activeProfileID) { _ in
            draggedSlot = nil
            hoverSlot = nil
        }
        .sheet(item: pickerSheetBinding) { wrap in
            AppPickerSheet { picked in
                if let bid = picked {
                    prefs.setPinnedBundleID(bid, at: wrap.value)
                }
                pickerForSlot = nil
            }
        }
    }

    // MARK: Layers

    @ViewBuilder
    private var wheelBackground: some View {
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
            Circle()
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.8)
        }
        .frame(width: diameter, height: diameter)
        // Same soft-edge fade as the live Halo: opaque to 84 %, then a
        // linear alpha falloff to fully transparent at the geometric rim.
        .mask(
            Circle()
                .fill(
                    RadialGradient(
                        stops: [
                            .init(color: .black, location: 0.0),
                            .init(color: .black, location: 0.84),
                            .init(color: .clear, location: 1.0),
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: diameter / 2
                    )
                )
        )
        .shadow(color: .black.opacity(0.20), radius: 16, x: 0, y: 6)
    }

    private var sectors: some View {
        ForEach(0..<prefs.slotCount, id: \.self) { slot in
            SectorShape(
                index: slot,
                sectorCount: prefs.slotCount,
                gapDegrees: 1.0
            )
            .fill(sectorFill(for: slot))
            .overlay(
                SectorShape(index: slot, sectorCount: prefs.slotCount, gapDegrees: 1.0)
                    .stroke(Color.primary.opacity(0.05), lineWidth: 0.5)
            )
            .frame(width: diameter, height: diameter)
            .allowsHitTesting(false)
        }
    }

    private var slotButtons: some View {
        ForEach(0..<prefs.slotCount, id: \.self) { slot in
            slotButton(slot: slot)
                .offset(slotOffset(slot: slot))
        }
    }

    @ViewBuilder
    private var centerHub: some View {
        ZStack {
            Circle()
                .fill(Color.primary.opacity(0.06))
                .overlay(
                    Circle().strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                )
            Text("Halo")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(.tint)
        }
        .frame(width: hubDiameter, height: hubDiameter)
        .allowsHitTesting(false)
    }

    // MARK: Slot button

    @ViewBuilder
    private func slotButton(slot: Int) -> some View {
        let bundleID = prefs.pinnedBundleIDs[safe: slot] ?? nil
        let isPinned = bundleID != nil
        let isDragSource = draggedSlot == slot
        let isDropTarget = hoverSlot == slot && draggedSlot != nil && draggedSlot != slot

        Button {
            if isPinned {
                editingSlot = slot
            } else {
                pickerForSlot = slot
            }
        } label: {
            slotIcon(bundleID: bundleID)
                .frame(width: iconBoxSize, height: iconBoxSize)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .opacity(isDragSource ? 0.40 : 1.0)
        .overlay(dropTargetOverlay(isHighlighted: isDropTarget))
        .popover(isPresented: editingBinding(for: slot), arrowEdge: .top) {
            SlotEditorPopover(
                slot: slot,
                prefs: prefs,
                onChangeApp: {
                    editingSlot = nil
                    pickerForSlot = slot
                }
            )
        }
        .help(helpText(slot: slot, bundleID: bundleID))
        // Only pinned slots can be drag sources — dragging an empty
        // slot would surprise users by clearing an unrelated pin via
        // the swap semantic.
        .modifier(SlotDragSource(slot: slot, enabled: isPinned, draggedSlot: $draggedSlot))
        .onDrop(of: [UTType.plainText], delegate: SlotDropDelegate(
            targetSlot: slot,
            prefs: prefs,
            draggedSlot: $draggedSlot,
            hoverSlot: $hoverSlot
        ))
    }

    /// 2pt accent stroke around the drop-target slot during a drag.
    /// Inset enough to read clearly without clipping the icon glyph.
    @ViewBuilder
    private func dropTargetOverlay(isHighlighted: Bool) -> some View {
        if isHighlighted {
            RoundedRectangle(cornerRadius: 11, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .padding(2)
        }
    }

    @ViewBuilder
    private func slotIcon(bundleID: String?) -> some View {
        if let id = bundleID, let icon = AppIconResolver.icon(for: id) {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
                .frame(width: iconVisualSize, height: iconVisualSize)
        } else {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .strokeBorder(
                        Color.primary.opacity(0.30),
                        style: StrokeStyle(lineWidth: 1, dash: [3, 3])
                    )
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(width: iconVisualSize, height: iconVisualSize)
        }
    }

    // MARK: Helpers

    private func sectorFill(for slot: Int) -> Color {
        guard let id = prefs.pinnedBundleIDs[safe: slot] ?? nil else {
            return Color.primary.opacity(0.04)
        }
        // 1. user-set colour wins
        if let override = prefs.identityOverride(for: id) {
            return override.swiftUIColor.opacity(0.10)
        }
        // 2. icon-derived identity colour — trusted as-is, no chroma floor.
        // Matches the live wheel exactly: every app's sector reflects its
        // own icon, never a borrowed palette entry.
        if let icon = AppIconResolver.icon(for: id),
           let extracted = extractor.extract(from: icon) {
            return extracted.swiftUIColor.opacity(0.10)
        }
        // 3. extractor returned nil (greyscale icon, no chromatic pixels) →
        // neutral, identical to the live wheel's chroma-0 fallback.
        return Color.primary.opacity(0.04)
    }

    private func slotOffset(slot: Int) -> CGSize {
        let p = RadialGeometry.center(
            of: slot,
            sectorCount: prefs.slotCount,
            radius: iconRadius
        )
        return CGSize(width: p.x, height: -p.y)
    }

    private func editingBinding(for slot: Int) -> Binding<Bool> {
        Binding(
            get: { editingSlot == slot },
            set: { isOn in
                if !isOn && editingSlot == slot { editingSlot = nil }
            }
        )
    }

    private var pickerSheetBinding: Binding<WheelSlotID?> {
        Binding(
            get: { pickerForSlot.map { WheelSlotID(value: $0) } },
            set: { pickerForSlot = $0?.value }
        )
    }

    private func helpText(slot: Int, bundleID: String?) -> String {
        if let id = bundleID,
           let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
            let name = (url.lastPathComponent as NSString).deletingPathExtension
            return String(format: NSLocalizedString("%@ · drag to swap slots",
                                                    comment: "Slot tooltip when pinned"),
                          name)
        }
        return NSLocalizedString("Auto · drop an app here to move it",
                                 comment: "Slot tooltip when empty")
    }
}

/// Conditional `.onDrag` modifier. Only pinned slots may be drag
/// sources — applying `.onDrag` to an empty slot would let the user
/// initiate a swap with an empty payload, which under the swap semantic
/// would silently clear the destination's pin. Side-effecting set of
/// `draggedSlot` happens in the closure so the source pill dims as soon
/// as SwiftUI starts the drag.
private struct SlotDragSource: ViewModifier {
    let slot: Int
    let enabled: Bool
    @Binding var draggedSlot: Int?

    func body(content: Content) -> some View {
        if enabled {
            content.onDrag {
                draggedSlot = slot
                return NSItemProvider(object: String(slot) as NSString)
            }
        } else {
            content
        }
    }
}

/// Drop delegate for one wheel slot. Source identity comes from the
/// view-local `draggedSlot` `@State` (set by `SlotDragSource`) — we
/// don't read the NSItemProvider payload because the binding is
/// always available within the same view tree and avoids the async
/// load-back dance. `performDrop` routes through
/// `AppPreferences.swapPins(at:and:)` so the active profile is
/// mutated atomically.
private struct SlotDropDelegate: DropDelegate {
    let targetSlot: Int
    let prefs: AppPreferences
    @Binding var draggedSlot: Int?
    @Binding var hoverSlot: Int?

    func dropEntered(info: DropInfo) {
        guard let source = draggedSlot, source != targetSlot else { return }
        hoverSlot = targetSlot
    }

    func dropExited(info: DropInfo) {
        if hoverSlot == targetSlot { hoverSlot = nil }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        guard let source = draggedSlot, source != targetSlot else {
            return DropProposal(operation: .forbidden)
        }
        return DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        defer {
            draggedSlot = nil
            hoverSlot = nil
        }
        guard let source = draggedSlot, source != targetSlot else { return false }
        prefs.swapPins(at: source, and: targetSlot)
        return true
    }
}

/// `Int`s aren't `Identifiable` by themselves; wrap for `.sheet(item:)`.
private struct WheelSlotID: Identifiable {
    let value: Int
    var id: Int { value }
}

// MARK: - Slot editor popover

private struct SlotEditorPopover: View {
    let slot: Int
    @ObservedObject var prefs: AppPreferences
    let onChangeApp: () -> Void

    @State private var swatch: Color = .gray

    private var bundleID: String? {
        prefs.pinnedBundleIDs[safe: slot] ?? nil
    }

    private var displayName: String {
        guard let id = bundleID else { return NSLocalizedString("Auto", comment: "") }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else {
            return id
        }
        return (url.lastPathComponent as NSString).deletingPathExtension
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header — icon + name + slot label
            HStack(spacing: 10) {
                if let id = bundleID, let icon = AppIconResolver.icon(for: id) {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                        .frame(width: 40, height: 40)
                } else {
                    Image(systemName: "questionmark.app.dashed")
                        .font(.system(size: 28))
                        .foregroundStyle(.secondary)
                        .frame(width: 40, height: 40)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text(slotLabel)
                        .font(.system(size: 10, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)
                    Text(displayName)
                        .font(.headline)
                }
                Spacer(minLength: 0)
            }

            Divider()

            // Identity colour row
            HStack {
                Text("Identity colour")
                    .font(.callout)
                Spacer()
                ColorPicker("", selection: $swatch, supportsOpacity: false)
                    .labelsHidden()
                    .compatOnChange(of: swatch) { new in
                        if let id = bundleID,
                           let identity = IdentityColor.fromSwiftUI(new) {
                            prefs.setIdentityOverride(identity, for: id)
                        }
                    }
                Button("Reset") {
                    if let id = bundleID {
                        prefs.setIdentityOverride(nil, for: id)
                        loadSwatch()
                    }
                }
                .buttonStyle(.borderless)
            }

            Divider()

            // Action row
            HStack {
                Button("Change…") { onChangeApp() }
                Spacer()
                Button("Clear pin", role: .destructive) {
                    prefs.setPinnedBundleID(nil, at: slot)
                }
            }
        }
        .padding(16)
        .frame(width: 280)
        .onAppear(perform: loadSwatch)
    }

    private var slotLabel: String {
        String(format: NSLocalizedString("Slot %d", comment: "Slot index label in editor"), slot)
    }

    private func loadSwatch() {
        guard let id = bundleID else { swatch = .gray; return }
        if let override = prefs.identityOverride(for: id) {
            swatch = override.swiftUIColor
        } else {
            swatch = .gray
        }
    }
}

// MARK: - Small utility

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
