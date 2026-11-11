// Color(hex:) initializer — converts a 24-bit RGB hex literal to a SwiftUI Color.
import SwiftUI

extension Color {
    /// - Parameter hex: 24-bit RGB value, e.g. `0xFF8800`
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8) & 0xFF) / 255
        let b = Double(hex & 0xFF) / 255
        self.init(red: r, green: g, blue: b)
    }
}
