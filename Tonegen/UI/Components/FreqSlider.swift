// Logarithmic frequency slider with decade tick marks and octave haptics.
import SwiftUI

// Major decade stops and sub-decade stops (matching the mockup).
private let majorTicks: [Double] = [20, 100, 1000, 10000, 20000]
private let minorTicks: [Double] = [
    30, 40, 50, 60, 70, 80, 90,
    200, 300, 400, 500, 600, 700, 800, 900,
    2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000
]
private let decadeLabels: [(String, Double)] = [
    ("20", 20), ("100", 100), ("1k", 1000), ("10k", 10000), ("20k", 20000)
]

struct FreqSlider: View {
    @Binding var frequencyHz: Double
    var accentColor: Color = Tokens.Color.channelL

    @State private var octave: Int = 0
    @State private var hitEdge = false
    @State private var wasAtEdge = false

    var body: some View {
        VStack(spacing: 0) {
            GeometryReader { geo in
                // Inset the thumb's travel so it stays inside the track at both ends.
                let inset = sliderThumbWidth / 2
                let travel = max(Double(geo.size.width) - sliderThumbWidth, 1)
                let pos = freqToSliderPosition(frequencyHz)
                let thumbX = inset + pos * travel

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

                    // Major ticks (taller)
                    ForEach(majorTicks, id: \.self) { tick in
                        let tx = inset + freqToSliderPosition(tick) * travel
                        Rectangle()
                            .fill(Tokens.Color.strokeSoft)
                            .frame(width: 1, height: 7)
                            .offset(x: tx - 0.5)
                    }

                    // Minor ticks (shorter)
                    ForEach(minorTicks, id: \.self) { tick in
                        let tx = inset + freqToSliderPosition(tick) * travel
                        Rectangle()
                            .fill(Tokens.Color.strokeSoft)
                            .frame(width: 1, height: 4)
                            .offset(x: tx - 0.5)
                    }

                    // Thumb (taller than LinearSlider to match mockup)
                    sliderThumb(accentColor: accentColor)
                        .frame(width: sliderThumbWidth, height: 28)
                        .offset(x: thumbX - inset)
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { drag in
                            updateFreq(x: Double(drag.location.x), travel: travel)
                        }
                )
            }
            .frame(height: 48)
            .contentShape(Rectangle())

            // Decade labels
            HStack {
                ForEach(decadeLabels, id: \.1) { label, freq in
                    Text(label)
                        .font(Tokens.Font.readoutXs)
                        .foregroundStyle(Tokens.Color.textGhost)
                        .frame(maxWidth: .infinity, alignment: freqLabelAlignment(freq))
                }
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: octave)
        .sensoryFeedback(.impact(weight: .light), trigger: hitEdge)
        .accessibilityElement()
        .accessibilityLabel("Frequency")
        .accessibilityValue(accessibilityFreqValue)
        .accessibilityAdjustableAction { direction in
            let step: Double = direction == .increment ? pow(2, 1.0 / 12) : pow(2, -1.0 / 12)
            let newFreq = min(max(frequencyHz * step, 20), 20000)
            frequencyHz = newFreq
        }
    }

    private func updateFreq(x: Double, travel: Double) {
        let pos = min(max((x - sliderThumbWidth / 2) / travel, 0), 1)
        let newFreq = sliderPositionToFreq(pos)
        frequencyHz = newFreq

        let newOctave = Int(log2(newFreq).rounded(.down))
        if newOctave != octave { octave = newOctave }

        let atEdge = pos == 0 || pos == 1
        if atEdge, !wasAtEdge { hitEdge.toggle() }
        wasAtEdge = atEdge
    }

    private func freqLabelAlignment(_ freq: Double) -> Alignment {
        if freq == 20 { return .leading }
        if freq == 20000 { return .trailing }
        return .center
    }

    private var accessibilityFreqValue: String {
        let (note, oct, cents) = freqToNote(frequencyHz)
        let sign = cents >= 0 ? "+" : ""
        if frequencyHz >= 1000 {
            return String(
                format: "%.2f kilohertz, %@%d, %@%d cents",
                frequencyHz / 1000,
                note,
                oct,
                sign,
                cents
            )
        }
        return String(format: "%.0f hertz, %@%d, %@%d cents", frequencyHz, note, oct, sign, cents)
    }
}

#if DEBUG
    #Preview {
        @Previewable @State var freq: Double = 440
        VStack(spacing: 24) {
            FreqSlider(frequencyHz: $freq)
            Text(String(format: "%.1f Hz", freq))
                .foregroundStyle(Tokens.Color.channelL)
                .font(Tokens.Font.readoutMd)
        }
        .padding()
        .background(Tokens.Color.bg)
    }
#endif
