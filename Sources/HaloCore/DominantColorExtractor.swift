import Foundation
#if canImport(AppKit) && canImport(CoreImage)
import AppKit
import CoreImage
import CoreGraphics

/// Extracts the dominant brand color from an app icon.
///
/// Strategy: rasterise the icon at a fixed size, then build a chroma-weighted
/// hue histogram (24 bins of 15°). For each opaque pixel we reject the
/// near-greyscale (chroma < 0.04) and near-extreme-lightness pixels (so the
/// white background of icons like Codex doesn't drown out the brand element),
/// then accumulate weight = chroma × alpha into the pixel's hue bin together
/// with the running RGB sum. The winning bin's weighted average RGB is what we
/// return.
///
/// Why a histogram instead of CIKMeans: K-means with k=3 collapses small but
/// chromatic elements into the dominant cluster. For icons with a white
/// background and a tiny coloured glyph (Codex, plenty of macOS Tahoe icons)
/// the brand colour ends up as no cluster at all and we get back a near-grey,
/// which after conflict resolution can land arbitrarily far from the icon's
/// real identity. The histogram keeps every chromatic pixel and lets the
/// dominant *hue* win, regardless of its share of total pixels.
public struct DominantColorExtractor {
    public init() {}

    /// Render side length, in pixels. 96 is enough to capture brand colour
    /// while keeping the per-icon cost negligible (~9k pixels).
    private let renderSide = 96

    /// Per-pixel chroma below which a pixel is treated as greyscale and
    /// excluded from the histogram.
    private let pixelChromaFloor = 0.04

    /// Pixels brighter than this are likely the white card behind a brand
    /// glyph; pixels darker than this are likely shadows. Both lose to the
    /// glyph itself.
    private let lightnessLow = 0.20
    private let lightnessHigh = 0.92

    public func extract(from image: NSImage) -> IdentityColor? {
        guard let cg = rasterize(image: image, size: renderSide) else { return nil }
        return extract(fromBitmap: cg)
    }

    public func extract(from ciImage: CIImage) -> IdentityColor? {
        let context = CIContext(options: [.workingColorSpace: NSNull()])
        guard let cg = context.createCGImage(ciImage, from: ciImage.extent) else { return nil }
        return extract(fromBitmap: cg)
    }

    // MARK: - Internals

    private func rasterize(image: NSImage, size: Int) -> CGImage? {
        guard let cs = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: nil,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: cs,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }

        let prev = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
        image.draw(in: CGRect(x: 0, y: 0, width: size, height: size),
                   from: .zero,
                   operation: .copy,
                   fraction: 1.0)
        NSGraphicsContext.current = prev
        return ctx.makeImage()
    }

    private func extract(fromBitmap cg: CGImage) -> IdentityColor? {
        guard let provider = cg.dataProvider,
              let data = provider.data,
              let ptr = CFDataGetBytePtr(data)
        else { return nil }

        let width = cg.width
        let height = cg.height
        let bytesPerRow = cg.bytesPerRow

        let binCount = 24
        let binSize = 360.0 / Double(binCount)
        var weight = [Double](repeating: 0, count: binCount)
        var sumR = [Double](repeating: 0, count: binCount)
        var sumG = [Double](repeating: 0, count: binCount)
        var sumB = [Double](repeating: 0, count: binCount)

        for y in 0..<height {
            let row = y * bytesPerRow
            for x in 0..<width {
                let i = row + x * 4
                let a = Double(ptr[i + 3]) / 255.0
                guard a > 0.5 else { continue }
                let r = clamp01(Double(ptr[i + 0]) / 255.0 / a)
                let g = clamp01(Double(ptr[i + 1]) / 255.0 / a)
                let b = clamp01(Double(ptr[i + 2]) / 255.0 / a)

                let id = IdentityColor.fromSRGB(r: r, g: g, b: b)
                guard id.chroma > pixelChromaFloor else { continue }
                guard id.lightness > lightnessLow && id.lightness < lightnessHigh else { continue }

                let bin = max(0, min(binCount - 1, Int(id.hue / binSize)))
                let w = id.chroma * a
                weight[bin] += w
                sumR[bin] += r * w
                sumG[bin] += g * w
                sumB[bin] += b * w
            }
        }

        guard let best = weight.indices.max(by: { weight[$0] < weight[$1] }),
              weight[best] > 0
        else { return nil }

        let total = weight[best]
        return IdentityColor.fromSRGB(
            r: sumR[best] / total,
            g: sumG[best] / total,
            b: sumB[best] / total
        )
    }
}

private func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }

#endif
