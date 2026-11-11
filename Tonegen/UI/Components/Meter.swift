// 14-segment vertical RMS level meter with color zones.
import SwiftUI

struct Meter: View {
    /// Current level in [0, 1] (linear scale).
    let level: Float
    var accentColor: Color = Tokens.Color.channelL
    /// Channel name, spoken as "<label> output level, RMS".
    var label: String = "Output"

    private let segmentCount = 14
    // Top 2 = hot (red), next 3 = warn (amber), rest = normal (green).
    private let hotFrom = 12
    private let warnFrom = 9

    var body: some View {
        VStack(spacing: 2) {
            ForEach((0 ..< segmentCount).reversed(), id: \.self) { seg in
                let lit = Float(seg) < Float(segmentCount) * level
                let segColor = segmentColor(seg)
                RoundedRectangle(cornerRadius: 1)
                    .fill(lit ? segColor : Tokens.Color.meterUnlit)
                    .shadow(color: lit ? segColor.opacity(0.5) : .clear, radius: 2)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(width: 8)
        .accessibilityElement()
        .accessibilityLabel("\(label) output level, RMS")
        .accessibilityValue(String(format: "%.0f percent of scale", level * 100))
    }

    private func segmentColor(_ seg: Int) -> Color {
        if seg >= hotFrom { return Tokens.Color.meterHot }
        if seg >= warnFrom { return Tokens.Color.meterWarn }
        return Tokens.Color.meterNormal
    }
}

#if DEBUG
    #Preview {
        HStack(spacing: 16) {
            Meter(level: 0.3)
            Meter(level: 0.7)
            Meter(level: 0.95)
        }
        .frame(height: 80)
        .padding()
        .background(Tokens.Color.bg)
    }
#endif
