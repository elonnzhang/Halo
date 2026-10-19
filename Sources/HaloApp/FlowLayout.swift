import SwiftUI
import HaloUI

/// Left-to-right row of chips that wraps onto new rows instead of scrolling.
/// The wrap rules live in `FlowGeometry` (HaloUI) so they are unit-tested;
/// this type only feeds it the children's ideal sizes and places the result.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    var lineSpacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrange(proposal.width ?? .infinity, subviews)
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? result.size.width
        return CGSize(width: width, height: result.size.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrange(bounds.width, subviews)
        for (subview, frame) in zip(subviews, result.frames) {
            subview.place(
                at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                anchor: .topLeading,
                proposal: ProposedViewSize(width: frame.width, height: frame.height)
            )
        }
    }

    private func arrange(_ maxWidth: CGFloat, _ subviews: Subviews) -> FlowGeometry.Result {
        FlowGeometry.layout(
            sizes: subviews.map { $0.sizeThatFits(.unspecified) },
            maxWidth: maxWidth,
            spacing: spacing,
            lineSpacing: lineSpacing
        )
    }
}
