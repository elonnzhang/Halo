import SwiftUI
import AppKit
import HaloCore

extension IdentityColor {
    /// Convert this OKLCH color into a SwiftUI Color via sRGB (gamut-clipped).
    public var swiftUIColor: Color {
        let rgb = toSRGB()
        return Color(.sRGB,
                     red: max(0, min(1, rgb.r)),
                     green: max(0, min(1, rgb.g)),
                     blue: max(0, min(1, rgb.b)),
                     opacity: 1.0)
    }

    public func swiftUIColor(opacity: Double) -> Color {
        let rgb = toSRGB()
        return Color(.sRGB,
                     red: max(0, min(1, rgb.r)),
                     green: max(0, min(1, rgb.g)),
                     blue: max(0, min(1, rgb.b)),
                     opacity: opacity)
    }

    /// Inverse helper: take a SwiftUI Color and convert to OKLCH.
    /// Returns nil if the color can't be resolved to sRGB (rare; happens with
    /// dynamic colors that don't have a stable resolved value).
    public static func fromSwiftUI(_ color: Color) -> IdentityColor? {
        let ns = NSColor(color).usingColorSpace(.sRGB)
        guard let resolved = ns else { return nil }
        return IdentityColor.fromSRGB(
            r: Double(resolved.redComponent),
            g: Double(resolved.greenComponent),
            b: Double(resolved.blueComponent)
        )
    }
}
