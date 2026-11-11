// Grows a control's tappable area to Apple's 44 pt minimum without growing its layout.
import SwiftUI

private let minimumHitSide: CGFloat = 44

private struct ExpandedHitArea: ViewModifier {
    /// Most the area may grow sideways. Rows of controls pass half their inter-item
    /// spacing so neighbouring areas touch but never overlap.
    let maxHorizontalGrowth: CGFloat

    @State private var size: CGSize = .zero

    func body(content: Content) -> some View {
        let v = max(0, (minimumHitSide - size.height) / 2)
        let h = min(maxHorizontalGrowth, max(0, (minimumHitSide - size.width) / 2))
        // Pad, mark the padded rect as the hit shape, then cancel the padding so the
        // dense layout is unchanged. Measuring beats hardcoding: control heights vary
        // with Dynamic Type.
        content
            .onGeometryChange(for: CGSize.self, of: \.size) { size = $0 }
            .padding(.vertical, v)
            .padding(.horizontal, h)
            .contentShape(Rectangle())
            .padding(.vertical, -v)
            .padding(.horizontal, -h)
    }
}

extension View {
    /// Makes the view at least 44 pt tall (and wide, up to `maxHorizontalGrowth` per side)
    /// for hit testing only. Apply to a Button's label, or before a gesture.
    func expandedHitArea(maxHorizontalGrowth: CGFloat = 0) -> some View {
        modifier(ExpandedHitArea(maxHorizontalGrowth: maxHorizontalGrowth))
    }
}
