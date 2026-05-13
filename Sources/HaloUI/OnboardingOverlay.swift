import AppKit
import SwiftUI

/// One-shot tip shown the first time the user summons Halo. Renders as
/// a **small floating chip positioned next to Halo**, not as a
/// full-screen overlay — Halo is already at the cursor, so the tip
/// should be there too rather than fixed at screen centre. The chip ignores
/// pointer events so the user can drive Halo without the tip getting
/// in the way; it auto-dismisses after `displaySeconds` or when Halo
/// itself closes (caller invokes `dismiss()` on commit / cancel).
@MainActor
public final class OnboardingOverlay {
    public static let defaultsKey = "halo.onboarding.shown"
    public static let displaySeconds: TimeInterval = 8

    private var window: NSPanel?

    public init() {}

    public static var hasBeenShown: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    /// Show the tip beside the Halo panel. Auto-dismisses after
    /// `displaySeconds`. Records a UserDefaults flag so it only ever
    /// appears once.
    public func showIfNeeded(over panel: NSWindow) {
        guard !Self.hasBeenShown else { return }
        present(over: panel)
        UserDefaults.standard.set(true, forKey: Self.defaultsKey)
    }

    public func dismiss() {
        window?.orderOut(nil)
        window = nil
    }

    private func present(over halo: NSWindow) {
        // Visible chip vs. outer panel: the panel is much larger so the
        // soft drop shadow has room to fade out to fully transparent
        // before hitting the panel's rectangular bound. Positioning uses
        // chip-center math (not panel-corner math) so the visible chip
        // still lands just below Halo regardless of the panel padding.
        let chipSize = NSSize(width: 320, height: 76)
        let panelMargin: CGFloat = 50
        let panelSize = NSSize(
            width: chipSize.width + 2 * panelMargin,
            height: chipSize.height + 2 * panelMargin
        )
        let frame = chipFrame(forHalo: halo.frame,
                              on: halo.screen ?? NSScreen.main,
                              chipSize: chipSize,
                              panelSize: panelSize)

        let w = NSPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        w.level = NSWindow.Level(rawValue: NSWindow.Level.floating.rawValue + 1)
        w.isOpaque = false
        w.backgroundColor = .clear
        w.hasShadow = false
        // Pass clicks through to Halo underneath — the tip is purely
        // informational, not interactive.
        w.ignoresMouseEvents = true
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.contentView = NSHostingView(rootView: OnboardingChip())
        w.alphaValue = 0
        w.orderFrontRegardless()
        window = w

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            w.animator().alphaValue = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.displaySeconds) { [weak self] in
            self?.dismiss()
        }
    }

    /// Position the chip just below Halo by default; flip above when
    /// Halo is near the bottom of the screen. Math is done in *chip*
    /// coordinates and converted to panel coordinates at the end so the
    /// chip's visible centre sits at the same place regardless of how
    /// much padding the panel carries for its shadow.
    private func chipFrame(
        forHalo haloFrame: NSRect,
        on screen: NSScreen?,
        chipSize: NSSize,
        panelSize: NSSize
    ) -> NSRect {
        let screenFrame = screen?.visibleFrame ?? .zero
        let gap: CGFloat = 18

        // Where the chip's centre should land.
        var chipCenterX = haloFrame.midX
        var chipCenterY = haloFrame.minY - chipSize.height / 2 - gap

        // Flip above if the chip wouldn't fit below.
        if chipCenterY - chipSize.height / 2 < screenFrame.minY + 8 {
            chipCenterY = haloFrame.maxY + chipSize.height / 2 + gap
        }
        // Clamp the chip itself to the visible screen.
        let chipMinCenterX = screenFrame.minX + chipSize.width / 2 + 8
        let chipMaxCenterX = screenFrame.maxX - chipSize.width / 2 - 8
        chipCenterX = max(chipMinCenterX, min(chipMaxCenterX, chipCenterX))

        // Convert centre to panel origin (chip is centred inside the panel).
        let panelOrigin = NSPoint(
            x: chipCenterX - panelSize.width / 2,
            y: chipCenterY - panelSize.height / 2
        )
        return NSRect(origin: panelOrigin, size: panelSize)
    }
}

// MARK: - SwiftUI chip

private struct OnboardingChip: View {
    @State private var appear = false

    private let cornerRadius: CGFloat = 12

    var body: some View {
        // ZStack with the RoundedRectangle as the *bottom* fill is more
        // reliable than `.background(_:).clipShape(_:)` on Liquid Glass —
        // the latter can leak its material a fraction past the clipping
        // path at certain DPIs, showing the visible square panel edge.
        ZStack {
            chipShape
                .fill(.ultraThinMaterial)
            chipGlass
            chipContent
            chipShape
                .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.6)
        }
        .frame(width: 320, height: 76)
        // Two-layer shadow: a tight contact shadow + a much softer halo
        // that fades to transparent over 30+ points. The host panel has
        // 50pt of margin around the chip so the halo has room to die out
        // before it hits the panel's rectangular edge.
        .shadow(color: .black.opacity(0.16), radius: 4, x: 0, y: 2)
        .shadow(color: .black.opacity(0.12), radius: 22, x: 0, y: 10)
        // Outer container — centred in the larger panel.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : -4)
        .onAppear {
            withAnimation(.easeOut(duration: 0.22)) {
                appear = true
            }
        }
    }

    private var chipShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    /// On macOS 26 layer Liquid Glass on top of the ultraThinMaterial so
    /// the chip picks up the proper system glass refraction. Older
    /// systems get the material on its own; the result is the same kind
    /// of frosted backdrop without forcing a dark tint that fights the
    /// user's wallpaper.
    @ViewBuilder
    private var chipGlass: some View {
        #if compiler(>=6.3)
        if #available(macOS 26.0, *) {
            chipShape
                .fill(.clear)
                .glassEffect(in: chipShape)
        } else {
            EmptyView()
        }
        #else
        EmptyView()
        #endif
    }

    private var chipContent: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "cursorarrow.rays")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Color.accentColor)
                Text("Point a direction, release to switch")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.primary)
            }
            HStack(spacing: 6) {
                Text("ESC")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .tracking(0.4)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.primary.opacity(0.10))
                    )
                    .foregroundStyle(.secondary)
                Text("cancels · digit keys jump")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .frame(width: 320, height: 76, alignment: .leading)
    }
}
