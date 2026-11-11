// All design tokens — colors, typography, spacing, radii, stroke weights.
// Nothing in the view layer may hardcode these values.
import SwiftUI

/// A font described by its default-size metrics. It is resolved by `.font(_:)`
/// below, where it scales with Dynamic Type (and any `.dynamicTypeSize` cap in the
/// environment, which `UIFontMetrics` would ignore). At the default size the result
/// is identical to the fixed `Font.system(size:)` it replaced.
struct TokenFont {
    let size: CGFloat
    var weight: SwiftUI.Font.Weight = .regular
    var design: SwiftUI.Font.Design = .default
    var monospaced = false
    let style: SwiftUI.Font.TextStyle
}

enum Tokens {
    enum Color {
        // Surfaces
        static let bg = SwiftUI.Color(hex: 0x0A0908)
        static let surface = SwiftUI.Color(hex: 0x0C0A09)
        static let panel = SwiftUI.Color(hex: 0x0E0C0A)
        static let panelActive = SwiftUI.Color(hex: 0x16130F)
        static let stroke = SwiftUI.Color(hex: 0x2A2522)
        static let strokeSoft = SwiftUI.Color(hex: 0x1F1C19)

        // Text — contrast on bg / panel: 17.5 / 17.2, 9.9 / 9.7, 6.6 / 6.5, 4.6 / 4.5.
        // Ghost is the floor: anything dimmer fails WCAG AA for text, so keep dim
        // colours for decorative strokes only.
        static let textPrimary = SwiftUI.Color(hex: 0xF5F0E8)
        static let textSecondary = SwiftUI.Color(hex: 0xBDB6AC)
        static let textMuted = SwiftUI.Color(hex: 0x9B948B)
        static let textGhost = SwiftUI.Color(hex: 0x81796F)

        // Accents
        static let channelL = SwiftUI.Color(hex: 0xFFB147)
        static let channelR = SwiftUI.Color(hex: 0x5DDEF4)
        static let linked = SwiftUI.Color(hex: 0xD4D0C8)

        // Meters
        static let meterNormal = SwiftUI.Color(hex: 0x7DD3A0)
        static let meterWarn = SwiftUI.Color(hex: 0xFFB147)
        static let meterHot = SwiftUI.Color(hex: 0xFF5A4A)
        static let meterUnlit = SwiftUI.Color(hex: 0x1A1714)

        /// Status
        static let live = SwiftUI.Color(hex: 0x10B981)
    }

    enum Font {
        static let label = TokenFont(size: 10, weight: .medium, monospaced: true, style: .caption2)
        static let labelLg = TokenFont(size: 11, weight: .medium, style: .caption)
        static let body = TokenFont(size: 14, style: .body)
        static let title = TokenFont(size: 20, weight: .medium, style: .title3)

        static let readoutXL = TokenFont(size: 48, design: .monospaced, style: .largeTitle)
        static let readoutLg = TokenFont(size: 18, design: .monospaced, style: .body)
        static let readoutMd = TokenFont(size: 14, design: .monospaced, style: .subheadline)
        static let readoutSm = TokenFont(size: 11, design: .monospaced, style: .caption)
        static let readoutXs = TokenFont(size: 9, design: .monospaced, style: .caption2)

        // Glyph sizes for SF Symbols that sit beside text.
        static let iconXs = TokenFont(size: 10, weight: .medium, style: .caption2)
        static let iconSm = TokenFont(size: 12, weight: .medium, style: .caption)
        static let iconLg = TokenFont(size: 22, weight: .medium, style: .title3)
    }

    enum Spacing {
        static let xxs: CGFloat = 2
        static let xs: CGFloat = 4
        static let sm: CGFloat = 6
        static let md: CGFloat = 8
        static let lg: CGFloat = 12
        static let xl: CGFloat = 16
        static let xxl: CGFloat = 24
        static let panelPadH: CGFloat = 24
        static let panelPadV: CGFloat = 16
    }

    enum Radius {
        static let chip: CGFloat = 6
        static let panel: CGFloat = 10
        static let phone: CGFloat = 44
    }

    enum Stroke {
        static let hairline: CGFloat = 1
        static let normal: CGFloat = 1.5
    }
}

private struct TokenFontModifier: ViewModifier {
    let token: TokenFont
    @ScaledMetric private var size: CGFloat

    init(_ token: TokenFont) {
        self.token = token
        _size = ScaledMetric(wrappedValue: token.size, relativeTo: token.style)
    }

    func body(content: Content) -> some View {
        let base = Font.system(size: size, weight: token.weight, design: token.design)
        content.font(token.monospaced ? base.monospaced() : base)
    }
}

extension View {
    /// Applies a design-token font that scales with Dynamic Type.
    func font(_ token: TokenFont) -> some View {
        modifier(TokenFontModifier(token))
    }
}
