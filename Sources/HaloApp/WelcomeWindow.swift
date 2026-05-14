import AppKit
import SwiftUI
import HaloCore
import HaloUI

/// First-launch welcome shown as a **full-screen overlay** — dark scrim
/// across the whole display with a centred glass card on top. Replaces the
/// earlier titled-window approach so the experience feels like an iOS-style
/// onboarding overlay rather than a normal macOS window.
///
/// Behaviour:
/// - Auto-shows once after install (`halo.welcome.shown` UserDefaults flag).
/// - Settings → General → "Replay welcome guide" calls `showAgain()`.
/// - Dismisses on Get Started button, ESC, or click anywhere on the scrim.
/// - Live hotkey detection: pressing the configured chord lights the
///   "Summon" tip with a green checkmark — the user confirms it works
///   without needing to close the overlay first.
@MainActor
final class WelcomeWindowController {
    static let defaultsKey = "halo.welcome.shown"

    private var window: NSPanel?

    static var hasBeenShown: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    static func markShown() {
        UserDefaults.standard.set(true, forKey: defaultsKey)
    }

    func showIfNeeded() {
        guard !Self.hasBeenShown else { return }
        present()
        Self.markShown()
    }

    func showAgain() {
        present()
    }

    private func present() {
        guard window == nil else {
            window?.makeKeyAndOrderFront(nil)
            return
        }

        // Mount on the display the cursor is currently on.
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) }
            ?? NSScreen.main
            ?? NSScreen.screens.first!
        let frame = screen.frame

        let panel = WelcomeOverlayPanel(
            contentRect: frame,
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.level = .modalPanel
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // Inherit appearance from NSApp.appearance so the welcome card
        // flips with the user's theme. Pre-fix this was pinned to .darkAqua.

        let host = NSHostingView(rootView: WelcomeOverlay(
            prefs: AppPreferences.shared,
            onDismiss: { [weak self] in self?.dismiss() }
        ))
        host.frame = NSRect(origin: .zero, size: frame.size)
        host.autoresizingMask = [.width, .height]
        panel.contentView = host

        NSApp.setActivationPolicy(.regular)
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        self.window = panel
    }

    private func dismiss() {
        window?.orderOut(nil)
        window = nil
        NSApp.setActivationPolicy(.accessory)
    }
}

/// A plain borderless NSPanel sometimes refuses to become key on older
/// macOS; force the override so our local `keyDown` monitor fires.
private final class WelcomeOverlayPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - SwiftUI

private struct WelcomeOverlay: View {
    @ObservedObject var prefs: AppPreferences
    let onDismiss: () -> Void

    @State private var summonDetected = false
    @State private var monitor: Any?
    @State private var appear = false
    @Environment(\.colorScheme) private var colorScheme

    /// True when the welcome card is rendering against a dark NSAppearance.
    /// All hand-coded text + glass tints flip on this so the same comp
    /// reads as a "frosted dark hero" in dark mode and a "frosted light
    /// hero" in light mode.
    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        ZStack {
            scrim
            card
        }
        .ignoresSafeArea()
        .onAppear(perform: handleAppear)
        .onDisappear(perform: handleDisappear)
    }

    // MARK: Scrim

    private var scrim: some View {
        // Slight dim in light mode so the desktop behind doesn't compete
        // with the white card. A heavier 0.55 dim works on dark mode where
        // the card needs the contrast to read as a glass surface.
        Color.black.opacity(isDark ? 0.55 : 0.30)
            .contentShape(Rectangle())
            .onTapGesture { onDismiss() }
            .opacity(appear ? 1 : 0)
    }

    // MARK: Card

    private var card: some View {
        VStack(spacing: 0) {
            hero
            titleBlock
            tipsBlock
            getStartedButton
        }
        .padding(.top, 44)
        .padding(.horizontal, 40)
        .padding(.bottom, 30)
        .frame(width: 480)
        .background(cardBackground)
        .overlay(cardMeniscus)
        .overlay(cardRim)
        .overlay(alignment: .topTrailing) { escHint }
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .shadow(color: .black.opacity(0.50), radius: 42, x: 0, y: 20)
        .shadow(color: .black.opacity(0.20), radius: 8, x: 0, y: 4)
        .scaleEffect(appear ? 1 : 0.96)
        .opacity(appear ? 1 : 0)
    }

    /// Top-bright → bottom-dim rim stroke gives the card a glass meniscus
    /// rather than a flat outlined rectangle.
    private var cardRim: some View {
        // On light cards a white rim disappears into the white glass; use a
        // soft dark stroke instead so the card edge stays readable.
        let topColor: Color = isDark ? .white.opacity(0.18) : .black.opacity(0.12)
        let bottomColor: Color = isDark ? .white.opacity(0.04) : .black.opacity(0.03)
        return RoundedRectangle(cornerRadius: 24, style: .continuous)
            .strokeBorder(
                LinearGradient(
                    colors: [topColor, bottomColor],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 0.8
            )
            .allowsHitTesting(false)
    }

    /// Faint top-fade inside the rim that simulates a glass surface catching
    /// light from above. Subtle — barely visible but adds depth.
    private var cardMeniscus: some View {
        let highlight: Color = isDark ? .white.opacity(0.06) : .white.opacity(0.30)
        return RoundedRectangle(cornerRadius: 24, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [highlight, Color.clear],
                    startPoint: .top,
                    endPoint: .center
                )
            )
            .allowsHitTesting(false)
    }

    private var escHint: some View {
        Text("ESC")
            .font(.system(size: 10, weight: .medium, design: .rounded))
            .tracking(0.6)
            .foregroundStyle(.primary.opacity(0.45))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.primary.opacity(0.08))
                    .overlay(
                        Capsule(style: .continuous)
                            .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
                    )
            )
            .padding(16)
            .allowsHitTesting(false)
    }

    private var hero: some View {
        ZStack {
            // Soft glow halo behind the hero icon — only visible because the
            // card sits on a dark scrim. Tied to accentColor so it picks up
            // whatever the user has configured at the system level.
            Circle()
                .fill(Color.accentColor.opacity(0.32))
                .blur(radius: 26)
                .frame(width: 90, height: 90)
            Image(systemName: "circle.dashed.inset.filled")
                .font(.system(size: 58, weight: .light))
                .foregroundStyle(.tint)
        }
        .padding(.bottom, 18)
    }

    private var titleBlock: some View {
        VStack(spacing: 8) {
            Text("Welcome to Halo")
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
            Text("Radial app launcher for macOS — point a direction, switch apps.")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
        }
        .padding(.bottom, 28)
    }

    private var tipsBlock: some View {
        VStack(alignment: .leading, spacing: 18) {
            summonTip
            tipRow(
                index: 1,
                icon: "cursorarrow.rays",
                title: "Navigate",
                body: "Point the cursor at a slot and release the hotkey to switch. ESC cancels."
            )
            tipRow(
                index: 2,
                icon: "gearshape",
                title: "Customize",
                body: "Click the Halo icon in the menu bar to open Settings — pin apps, rebind the hotkey, switch language."
            )
        }
        .padding(.bottom, 30)
    }

    private var summonTip: some View {
        HStack(alignment: .top, spacing: 14) {
            iconChip(
                name: summonDetected ? "checkmark.circle.fill" : "command",
                tint: summonDetected ? successColor : Color.accentColor
            )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("Summon")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                    if summonDetected {
                        Text("Hotkey detected ✓")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                            .foregroundStyle(successColor)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    }
                }
                Text("Press ⌘⌥Space or double-tap ⌘ to bring up Halo.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(currentHotkeyHint)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(
                        summonDetected ? successColor : Color.primary.opacity(0.40)
                    )
            }
            Spacer(minLength: 0)
        }
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 10)
        .animation(.easeOut(duration: 0.4).delay(0.10), value: appear)
    }

    private func tipRow(
        index: Int,
        icon: String,
        title: LocalizedStringKey,
        body: LocalizedStringKey
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            iconChip(name: icon, tint: Color.accentColor)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text(body)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 10)
        .animation(.easeOut(duration: 0.4).delay(0.10 + 0.05 * Double(index)), value: appear)
    }

    /// Small tinted disc behind each tip icon. Mirrors macOS Mail / Notes
    /// onboarding cards where every step has a coloured leading badge.
    private func iconChip(name: String, tint: Color) -> some View {
        ZStack {
            Circle()
                .fill(tint.opacity(0.18))
            Circle()
                .strokeBorder(tint.opacity(0.30), lineWidth: 0.6)
            Image(systemName: name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(tint)
        }
        .frame(width: 32, height: 32)
    }

    private var getStartedButton: some View {
        // Dark mode keeps the original "bright white pill on dark glass"
        // look. Light mode flips to an accent-tinted pill because a white
        // pill on a light card vanishes into the background.
        let fillTop:   Color = isDark ? Color.white : Color.accentColor
        let fillBot:   Color = isDark ? Color.white.opacity(0.92) : Color.accentColor.opacity(0.92)
        let textColor: Color = isDark ? .black : .white
        let rimColor:  Color = isDark ? Color.black.opacity(0.06) : Color.black.opacity(0.10)
        return Button(action: onDismiss) {
            HStack(spacing: 6) {
                Text("Get Started")
                    .font(.system(size: 14, weight: .semibold))
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(textColor)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 13)
            .background(
                LinearGradient(
                    colors: [fillTop, fillBot],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay(
                Capsule(style: .continuous)
                    .strokeBorder(rimColor, lineWidth: 0.5)
            )
            .clipShape(Capsule(style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .keyboardShortcut(.defaultAction)
        .opacity(appear ? 1 : 0)
        .offset(y: appear ? 0 : 10)
        .animation(.easeOut(duration: 0.4).delay(0.30), value: appear)
    }

    @ViewBuilder
    private var cardBackground: some View {
        if #available(macOS 26.0, *) {
            Rectangle()
                .fill(.clear)
                .glassEffect(in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        } else {
            legacyCardBackground
        }
    }

    private var legacyCardBackground: some View {
        // The panel is borderless and transparent, so `.behindWindow` blending
        // samples the desktop wallpaper rather than the SwiftUI scrim above —
        // on a bright wallpaper (notably macOS 12 Monterey's default) the
        // hudWindow material renders near-white and the text becomes
        // unreadable. Lay an explicit theme-matched plate under the material
        // so contrast survives regardless of what sits behind the panel:
        // dark mode gets a near-black plate, light mode a near-white one.
        ZStack {
            isDark ? Color.black.opacity(0.72) : Color.white.opacity(0.82)
            VisualEffectBackground(
                material: .hudWindow,
                blendingMode: .behindWindow,
                state: .active
            )
            .opacity(0.55)
        }
    }

    private var successColor: Color {
        Color(red: 0.20, green: 0.85, blue: 0.45)
    }

    private var currentHotkeyDisplay: String {
        "\(prefs.hotkeyModifiers.symbols)\(KeyName.label(for: prefs.hotkeyKeyCode))"
    }

    /// Localised "Try it: press X now" — the chord substitutes for `%@`.
    private var currentHotkeyHint: String {
        String(format: NSLocalizedString("Try it: press %@ now", comment: ""),
               currentHotkeyDisplay)
    }

    // MARK: Lifecycle

    private func handleAppear() {
        withAnimation(.easeOut(duration: 0.30)) {
            appear = true
        }
        (NSApp.delegate as? AppDelegate)?.pauseHotkeyForOnboarding()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // ESC cancels the overlay outright.
            if Int(event.keyCode) == 53 {
                onDismiss()
                return nil
            }
            let evMods = HotkeyModifiers(nsEventFlags: event.modifierFlags)
            if UInt32(event.keyCode) == prefs.hotkeyKeyCode,
               evMods == prefs.hotkeyModifiers {
                if !summonDetected {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.7)) {
                        summonDetected = true
                    }
                }
                return nil
            }
            return event
        }
    }

    private func handleDisappear() {
        if let m = monitor { NSEvent.removeMonitor(m); monitor = nil }
        (NSApp.delegate as? AppDelegate)?.resumeHotkey()
    }
}
