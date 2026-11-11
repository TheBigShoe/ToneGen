// All design tokens — colors, typography, spacing, radii, stroke weights.
// Nothing in the view layer may hardcode these values.
import SwiftUI

enum Tokens {
    enum Color {
        // Surfaces
        static let bg = SwiftUI.Color(hex: 0x0A0908)
        static let surface = SwiftUI.Color(hex: 0x0C0A09)
        static let panel = SwiftUI.Color(hex: 0x0E0C0A)
        static let panelActive = SwiftUI.Color(hex: 0x16130F)
        static let stroke = SwiftUI.Color(hex: 0x2A2522)
        static let strokeSoft = SwiftUI.Color(hex: 0x1F1C19)

        // Text
        static let textPrimary = SwiftUI.Color(hex: 0xF5F0E8)
        static let textSecondary = SwiftUI.Color(hex: 0xA39C93)
        static let textMuted = SwiftUI.Color(hex: 0x807872)
        static let textGhost = SwiftUI.Color(hex: 0x4A453F)

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
        static let label = SwiftUI.Font.system(size: 10, weight: .medium).monospaced()
        static let labelLg = SwiftUI.Font.system(size: 11, weight: .medium)
        static let body = SwiftUI.Font.system(size: 14)
        static let title = SwiftUI.Font.system(size: 20, weight: .medium)

        static let readoutXL = SwiftUI.Font.system(size: 48, weight: .regular, design: .monospaced)
        static let readoutLg = SwiftUI.Font.system(size: 18, weight: .regular, design: .monospaced)
        static let readoutMd = SwiftUI.Font.system(size: 14, weight: .regular, design: .monospaced)
        static let readoutSm = SwiftUI.Font.system(size: 11, weight: .regular, design: .monospaced)
        static let readoutXs = SwiftUI.Font.system(size: 9, weight: .regular, design: .monospaced)
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
