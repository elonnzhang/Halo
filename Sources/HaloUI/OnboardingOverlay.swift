import AppKit
import SwiftUI

@MainActor
public final class OnboardingOverlay {
    public static let defaultsKey = "halo.onboarding.shown"
    public static let displaySeconds: TimeInterval = 8

    private var window: NSWindow?

    public init() {}

    public static var hasBeenShown: Bool {
        UserDefaults.standard.bool(forKey: defaultsKey)
    }

    /// Show the overlay over the HUD. Auto-dismisses after `displaySeconds`
    /// or on any click. Records a UserDefaults flag so it never reappears.
    public func showIfNeeded(over panel: NSWindow) {
        guard !Self.hasBeenShown else { return }
        present(over: panel)
        UserDefaults.standard.set(true, forKey: Self.defaultsKey)
    }

    public func dismiss() {
        window?.orderOut(nil)
        window = nil
    }

    private func present(over panel: NSWindow) {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let frame = screen.frame

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
        w.ignoresMouseEvents = false
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        w.contentView = NSHostingView(rootView: OnboardingContent(onDismiss: { [weak self] in
            self?.dismiss()
        }))
        w.orderFrontRegardless()
        window = w

        DispatchQueue.main.asyncAfter(deadline: .now() + Self.displaySeconds) { [weak self] in
            self?.dismiss()
        }
    }
}

private struct OnboardingContent: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .contentShape(Rectangle())
                .onTapGesture { onDismiss() }

            VStack(spacing: 18) {
                Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
                    .font(.system(size: 44, weight: .light))
                    .foregroundStyle(.white.opacity(0.9))
                Text("移动鼠标 / 按方向键 → 选择")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                Text("松开 → 切换 · ESC → 取消")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .padding(28)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(.white.opacity(0.1), lineWidth: 0.5)
            )
        }
    }
}
