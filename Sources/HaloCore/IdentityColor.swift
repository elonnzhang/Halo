import Foundation

/// A color expressed in OKLCH space — perceptually uniform and ideal for hue-distance arithmetic.
public struct IdentityColor: Hashable, Sendable, Codable {
    /// 0...1
    public var lightness: Double
    /// 0...~0.4 (chroma, like saturation)
    public var chroma: Double
    /// 0...360 (degrees)
    public var hue: Double

    public init(lightness: Double, chroma: Double, hue: Double) {
        self.lightness = lightness
        self.chroma = chroma
        self.hue = Self.wrapHue(hue)
    }

    public static func wrapHue(_ h: Double) -> Double {
        let r = h.truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }

    /// Smallest angular distance between two hues, 0...180.
    public static func hueDistance(_ a: Double, _ b: Double) -> Double {
        let raw = abs(wrapHue(a) - wrapHue(b))
        return min(raw, 360 - raw)
    }

    /// Convert sRGB (channels in 0...1, gamma-encoded) into OKLCH (CSS Color 4 reference math).
    public static func fromSRGB(r: Double, g: Double, b: Double) -> IdentityColor {
        let lr = sRGBToLinear(r)
        let lg = sRGBToLinear(g)
        let lb = sRGBToLinear(b)

        let l_ = 0.4122214708 * lr + 0.5363325363 * lg + 0.0514459929 * lb
        let m_ = 0.2119034982 * lr + 0.6806995451 * lg + 0.1073969566 * lb
        let s_ = 0.0883024619 * lr + 0.2817188376 * lg + 0.6299787005 * lb

        let l = cbrt(l_)
        let m = cbrt(m_)
        let s = cbrt(s_)

        let L = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bb = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s

        let C = sqrt(a * a + bb * bb)
        var H = atan2(bb, a) * 180.0 / .pi
        if H < 0 { H += 360 }
        return IdentityColor(lightness: L, chroma: C, hue: H)
    }

    /// Convert this OKLCH color back to gamma-encoded sRGB (0...1, may be out of gamut).
    public func toSRGB() -> (r: Double, g: Double, b: Double) {
        let h = hue * .pi / 180.0
        let a = chroma * cos(h)
        let b = chroma * sin(h)

        let l = lightness + 0.3963377774 * a + 0.2158037573 * b
        let m = lightness - 0.1055613458 * a - 0.0638541728 * b
        let s = lightness - 0.0894841775 * a - 1.2914855480 * b

        let lc = l * l * l
        let mc = m * m * m
        let sc = s * s * s

        let lr = 4.0767416621 * lc - 3.3077115913 * mc + 0.2309699292 * sc
        let lg = -1.2684380046 * lc + 2.6097574011 * mc - 0.3413193965 * sc
        let lb = -0.0041960863 * lc - 0.7034186147 * mc + 1.7076147010 * sc

        return (linearToSRGB(lr), linearToSRGB(lg), linearToSRGB(lb))
    }
}

private func sRGBToLinear(_ c: Double) -> Double {
    c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
}

private func linearToSRGB(_ c: Double) -> Double {
    let clamped = max(0.0, min(1.0, c))
    return clamped <= 0.0031308
        ? 12.92 * clamped
        : 1.055 * pow(clamped, 1.0 / 2.4) - 0.055
}

public enum IdentityPalette {
    /// Equal-arc fallback ring; base hue is 230° (aqua) per VISUAL §4.2.
    ///
    /// Range is now 1...12 (was 4...12) so the wheel can render a small
    /// `apps + 1` display when the user has fewer than four apps in
    /// rotation — the visible slot count is dynamic in that case and may
    /// drop as low as 1.
    public static func fallback(n: Int) -> [IdentityColor] {
        precondition((1...12).contains(n))
        let step = 360.0 / Double(n)
        return (0..<n).map { i in
            IdentityColor(lightness: 0.65, chroma: 0.18, hue: 230 + Double(i) * step)
        }
    }

    /// Locked Hue-8 palette used when N=8 and the user opts to restore it.
    public static func hue8() -> [IdentityColor] {
        [
            IdentityColor(lightness: 0.70, chroma: 0.13, hue: 230),
            IdentityColor(lightness: 0.52, chroma: 0.18, hue: 265),
            IdentityColor(lightness: 0.60, chroma: 0.24, hue: 295),
            IdentityColor(lightness: 0.58, chroma: 0.24, hue: 5),
            IdentityColor(lightness: 0.70, chroma: 0.18, hue: 45),
            IdentityColor(lightness: 0.65, chroma: 0.22, hue: 22),
            IdentityColor(lightness: 0.80, chroma: 0.15, hue: 80),
            IdentityColor(lightness: 0.67, chroma: 0.18, hue: 145),
        ]
    }
}

public struct IdentityConflictResolver {
    /// Chroma threshold below which an icon-extracted color is considered greyscale.
    public static let saturationFloor: Double = 0.12

    public init() {}

    /// Resolve a slate of candidate icon colors into the final per-slot identity palette.
    ///
    /// - Parameters:
    ///   - candidates: per-slot extracted color (nil = extraction failed)
    ///   - usageOrder: slot indices sorted from highest-frequency to lowest. Slots earlier
    ///     in this list win conflicts.
    ///   - n: slot count, 4...12
    ///   - useHue8: when true and n == 8, the Hue-8 palette replaces the fallback ring.
    public func resolve(
        candidates: [IdentityColor?],
        usageOrder: [Int],
        n: Int,
        useHue8: Bool
    ) -> [IdentityColor] {
        precondition(candidates.count == n)
        let fallback = (useHue8 && n == 8) ? IdentityPalette.hue8() : IdentityPalette.fallback(n: n)

        // Initial pass: replace nil / low-chroma candidates with fallback for that slot.
        var resolved: [IdentityColor] = (0..<n).map { i in
            guard let c = candidates[i], c.chroma >= Self.saturationFloor else {
                return fallback[i]
            }
            return c
        }

        let conflictThreshold = 360.0 / Double(n) * 0.6
        let pushAmount = 360.0 / Double(n) * 0.4

        // Resolve conflicts by walking the usage order: higher-frequency slots
        // are immovable. Each lower-frequency slot is allowed AT MOST ONE push
        // per pass — without this cap, a slot can chain multiple +pushAmount
        // shifts (one per previously-locked neighbour) and end up far from its
        // icon-derived hue. For N=8 the cascade can reach +126° and turn a
        // green icon into pink.
        var locked: Set<Int> = []
        for slot in usageOrder {
            for previous in locked {
                let d = IdentityColor.hueDistance(resolved[slot].hue, resolved[previous].hue)
                if d < conflictThreshold {
                    let pushedHue = resolved[slot].hue + pushAmount
                    resolved[slot] = IdentityColor(
                        lightness: resolved[slot].lightness,
                        chroma: resolved[slot].chroma,
                        hue: pushedHue
                    )
                    break
                }
            }
            locked.insert(slot)
        }
        return resolved
    }
}
