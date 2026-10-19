import CoreGraphics

/// Wrapping row layout for chip-like items: each item keeps its own size,
/// flows left to right and starts a new row when the next one would pass
/// `maxWidth`. Pure geometry so the wrap rules are testable; HaloApp's
/// `FlowLayout` adapts it to SwiftUI.
public enum FlowGeometry {
    public struct Result: Equatable, Sendable {
        /// One frame per input size, in input order, relative to the
        /// container's top-leading corner.
        public let frames: [CGRect]
        /// Bounding size of the placed items.
        public let size: CGSize
    }

    /// Items wider than `maxWidth` are clamped to it and sit alone on their
    /// row. A non-finite `maxWidth` keeps everything on one row.
    public static func layout(
        sizes: [CGSize],
        maxWidth: CGFloat,
        spacing: CGFloat,
        lineSpacing: CGFloat
    ) -> Result {
        let limit: CGFloat = maxWidth.isFinite ? max(maxWidth, 0) : .infinity
        // Absorbs float error so a row that fits exactly is not wrapped.
        let tolerance: CGFloat = 0.001

        var frames: [CGRect] = []
        frames.reserveCapacity(sizes.count)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var usedWidth: CGFloat = 0

        for raw in sizes {
            let width = min(sanitized(raw.width), limit)
            let height = sanitized(raw.height)
            if x > 0, x + width > limit + tolerance {
                y += rowHeight + lineSpacing
                x = 0
                rowHeight = 0
            }
            frames.append(CGRect(x: x, y: y, width: width, height: height))
            usedWidth = max(usedWidth, x + width)
            x += width + spacing
            rowHeight = max(rowHeight, height)
        }

        let totalHeight = frames.isEmpty ? 0 : y + rowHeight
        return Result(frames: frames, size: CGSize(width: usedWidth, height: totalHeight))
    }

    private static func sanitized(_ value: CGFloat) -> CGFloat {
        value.isFinite ? max(value, 0) : 0
    }
}
