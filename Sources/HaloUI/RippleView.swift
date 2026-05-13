import SwiftUI
import HaloCore

/// Full-screen identity-color ripple — Halo's signature commit feedback.
/// Per VISUAL §6: 280 → 600pt radius, 0 → 0.12 → 0 opacity, ~180ms ease-out.
public struct RippleView: View {
    let color: IdentityColor
    @State private var scale: CGFloat = (280.0 / 600.0)
    @State private var opacity: Double = 0.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init(color: IdentityColor) {
        self.color = color
    }

    public var body: some View {
        RadialGradient(
            gradient: Gradient(colors: [
                color.swiftUIColor(opacity: 0.12),
                color.swiftUIColor(opacity: 0.0),
            ]),
            center: .center,
            startRadius: 0,
            endRadius: 300
        )
        .scaleEffect(scale)
        .opacity(opacity)
        .allowsHitTesting(false)
        .onAppear { runAnimation() }
    }

    private func runAnimation() {
        let riseDur = reduceMotion ? 0.05 : 0.18
        let fadeDur = reduceMotion ? 0.04 : 0.06
        withAnimation(.easeOut(duration: riseDur)) {
            scale = 1.0
            opacity = 1.0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + riseDur) {
            withAnimation(.easeOut(duration: fadeDur)) {
                opacity = 0.0
            }
        }
    }
}
