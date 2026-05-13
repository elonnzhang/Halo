#!/usr/bin/env swift
// Renders Halo's app icon at every size required by Apple's .iconset bundle.
// Usage: swift scripts/render-icon.swift [outputDir]   (default: Resources/Halo.iconset)
//
// The icon is drawn entirely with CoreGraphics so it stays sharp at every size
// and the project does not need an SVG rasterizer in its build pipeline.

import AppKit
import CoreGraphics
import Foundation

let outputDir: String = {
    if CommandLine.arguments.count >= 2 {
        return CommandLine.arguments[1]
    }
    return "Resources/Halo.iconset"
}()

let sizes: [(name: String, pixels: Int)] = [
    ("icon_16x16.png",     16),
    ("icon_16x16@2x.png",  32),
    ("icon_32x32.png",     32),
    ("icon_32x32@2x.png",  64),
    ("icon_128x128.png",   128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",   256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",   512),
    ("icon_512x512@2x.png", 1024),
]

func draw(into ctx: CGContext, size: CGFloat) {
    let s = size
    // ------- 1. Squircle background -------
    let inset: CGFloat = s * 0.09
    let cornerRadius: CGFloat = s * 0.2235  // Apple-recommended squircle approximation
    let bgRect = CGRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset)

    let bgPath = CGPath(roundedRect: bgRect,
                        cornerWidth: cornerRadius,
                        cornerHeight: cornerRadius,
                        transform: nil)
    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    let colors: CFArray = [
        CGColor(srgbRed: 0.165, green: 0.165, blue: 0.196, alpha: 1.0),
        CGColor(srgbRed: 0.063, green: 0.063, blue: 0.078, alpha: 1.0)
    ] as CFArray
    let locations: [CGFloat] = [0.0, 1.0]
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: colors,
                                 locations: locations) {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: s * 0.5, y: s),
                               end: CGPoint(x: s * 0.5, y: 0),
                               options: [])
    }
    ctx.restoreGState()

    // ------- 2. Geometry shared between rings & petals -------
    let cx = s / 2
    let cy = s / 2
    let outerR = s * 0.34
    let innerR = s * 0.12

    // ------- 3. Eight petal outlines (dim) -------
    let petalCount = 8
    let petalSpan = (2 * .pi) / CGFloat(petalCount)
    let gap: CGFloat = 0.025 // radians

    func petalPath(slot: Int, lit: Bool) -> CGPath {
        let start = -CGFloat.pi / 2 + CGFloat(slot) * petalSpan - petalSpan / 2 + gap
        let end   = -CGFloat.pi / 2 + CGFloat(slot) * petalSpan + petalSpan / 2 - gap
        let p = CGMutablePath()
        p.addArc(center: CGPoint(x: cx, y: cy), radius: outerR,
                 startAngle: start, endAngle: end, clockwise: false)
        p.addArc(center: CGPoint(x: cx, y: cy), radius: innerR,
                 startAngle: end, endAngle: start, clockwise: true)
        p.closeSubpath()
        _ = lit
        return p
    }

    for slot in 0..<petalCount {
        ctx.addPath(petalPath(slot: slot, lit: false))
        ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.045)
        ctx.fillPath()

        ctx.addPath(petalPath(slot: slot, lit: false))
        ctx.setStrokeColor(red: 1, green: 1, blue: 1, alpha: 0.07)
        ctx.setLineWidth(max(0.5, s / 256))
        ctx.strokePath()
    }

    // ------- 4. Lit petal (slot 1, NE) — identity color -------
    let litSlot = 1
    ctx.saveGState()
    ctx.addPath(petalPath(slot: litSlot, lit: true))
    ctx.clip()
    let litColors: CFArray = [
        CGColor(srgbRed: 0.149, green: 0.647, blue: 0.894, alpha: 1.0), // #26A5E4
        CGColor(srgbRed: 0.231, green: 0.357, blue: 0.859, alpha: 1.0)  // #3B5BDB
    ] as CFArray
    if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                 colors: litColors,
                                 locations: [0.0, 1.0]) {
        ctx.drawLinearGradient(gradient,
                               start: CGPoint(x: cx, y: cy + outerR),
                               end:   CGPoint(x: cx + outerR, y: cy),
                               options: [])
    }
    ctx.restoreGState()

    // ------- 5. Halo glow ring (very subtle) -------
    ctx.setStrokeColor(red: 0.149, green: 0.647, blue: 0.894, alpha: 0.25)
    ctx.setLineWidth(max(0.5, s / 200))
    ctx.addEllipse(in: CGRect(x: cx - outerR - s * 0.02,
                              y: cy - outerR - s * 0.02,
                              width: (outerR + s * 0.02) * 2,
                              height: (outerR + s * 0.02) * 2))
    ctx.strokePath()

    // ------- 6. Center deadzone -------
    ctx.setFillColor(red: 1, green: 1, blue: 1, alpha: 0.05)
    ctx.addEllipse(in: CGRect(x: cx - innerR, y: cy - innerR,
                              width: innerR * 2, height: innerR * 2))
    ctx.fillPath()
    ctx.setStrokeColor(red: 1, green: 1, blue: 1, alpha: 0.18)
    ctx.setLineWidth(max(0.5, s / 256))
    ctx.addEllipse(in: CGRect(x: cx - innerR, y: cy - innerR,
                              width: innerR * 2, height: innerR * 2))
    ctx.strokePath()

    // ------- 7. Center dot -------
    let dotR = s * 0.018
    ctx.setFillColor(red: 0.149, green: 0.647, blue: 0.894, alpha: 1.0)
    ctx.addEllipse(in: CGRect(x: cx - dotR, y: cy - dotR,
                              width: dotR * 2, height: dotR * 2))
    ctx.fillPath()
}

func renderPNG(size: Int, path: String) throws {
    let s = CGFloat(size)
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 32
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let ctx = NSGraphicsContext.current!.cgContext
    draw(into: ctx, size: s)
    NSGraphicsContext.restoreGraphicsState()

    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "RenderIcon", code: 1)
    }
    let url = URL(fileURLWithPath: path)
    try data.write(to: url)
}

let fm = FileManager.default
try? fm.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
for (name, px) in sizes {
    let out = "\(outputDir)/\(name)"
    try renderPNG(size: px, path: out)
    print("wrote \(out) (\(px)px)")
}
print("done.")
