// Generic horizontal slider — linear scale, optional tick marks.
import SwiftUI

struct LinearSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    var ticks: [Double] = []
    var accentColor: Color = Tokens.Color.channelL
    var label: String = "Slider"

    @State private var hitEdge = false
    @State private var wasAtEdge = false

    var body: some View {
        GeometryReader { geo in
            let w = Double(geo.size.width)
            let pct = clamp((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let thumbX = pct * w

            ZStack(alignment: .leading) {
                // Track background
                Capsule()
                    .fill(Tokens.Color.stroke)
                    .frame(height: 2)
                    .frame(maxWidth: .infinity)

                // Filled portion
                Capsule()
                    .fill(accentColor)
                    .shadow(color: accentColor.opacity(0.4), radius: 3)
                    .frame(width: max(0, thumbX), height: 2)

                // Tick marks — centered on the track
                ForEach(ticks, id: \.self) { tick in
                    let tx = (tick - range.lowerBound) / (range.upperBound - range.lowerBound) * w
                    Rectangle()
                        .fill(Tokens.Color.strokeSoft)
                        .frame(width: 1, height: 6)
                        .offset(x: tx - 0.5)
                }

                // Thumb
                sliderThumb(accentColor: accentColor)
                    .offset(x: thumbX - 8)
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in updateValue(x: Double(drag.location.x), width: w) }
            )
        }
        .frame(height: 48)
        .contentShape(Rectangle())
        .sensoryFeedback(.impact(weight: .light), trigger: hitEdge)
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(String(format: "%.1f", value))
        .accessibilityAdjustableAction { direction in
            let step = (range.upperBound - range.lowerBound) / 100
            switch direction {
            case .increment: value = min(value + step, range.upperBound)
            case .decrement: value = max(value - step, range.lowerBound)
            @unknown default: break
            }
        }
    }

    private func updateValue(x: Double, width: Double) {
        let pct = clamp(x / width)
        value = pct * (range.upperBound - range.lowerBound) + range.lowerBound
        let atEdge = pct == 0 || pct == 1
        if atEdge, !wasAtEdge { hitEdge.toggle() }
        wasAtEdge = atEdge
    }
}

// MARK: - Shared thumb shape

func sliderThumb(accentColor: Color) -> some View {
    RoundedRectangle(cornerRadius: 3)
        .fill(Tokens.Color.bg)
        .frame(width: 16, height: 24)
        .overlay(
            RoundedRectangle(cornerRadius: 3)
                .stroke(accentColor, lineWidth: 1)
        )
        .overlay(
            Rectangle()
                .fill(accentColor.opacity(0.5))
                .frame(width: 1)
        )
        .shadow(color: accentColor.opacity(0.35), radius: 4)
}

// MARK: - Helpers

@inline(__always)
private func clamp(_ x: Double, lo: Double = 0, hi: Double = 1) -> Double {
    min(max(x, lo), hi)
}

// MARK: - Preview

#if DEBUG
    #Preview {
        @Previewable @State var amp: Double = -12
        VStack(spacing: 24) {
            LinearSlider(value: $amp, range: -60 ... 0, ticks: [-12, -24, -36, -48])
            Text(String(format: "%.1f dBFS", amp))
                .foregroundStyle(Tokens.Color.textSecondary)
                .font(Tokens.Font.readoutSm)
        }
        .padding()
        .background(Tokens.Color.bg)
    }
#endif
