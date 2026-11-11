// Large monospaced frequency readout with note name and cents deviation.
import SwiftUI

struct FrequencyDisplay: View {
    let frequencyHz: Double
    var accentColor: Color = Tokens.Color.channelL

    private var formatted: (value: String, unit: String) {
        if frequencyHz >= 10000 {
            return (String(format: "%.2f", frequencyHz / 1000), "kHz")
        } else if frequencyHz >= 1000 {
            return (String(format: "%.3f", frequencyHz / 1000), "kHz")
        }
        return (String(format: "%.2f", frequencyHz), "Hz")
    }

    private var noteLabel: String {
        let (name, oct, cents) = freqToNote(frequencyHz)
        let sign = cents >= 0 ? "+" : ""
        return "\(name)\(oct) \(sign)\(cents)¢"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xxs) {
            // Primary readout
            HStack(alignment: .lastTextBaseline, spacing: Tokens.Spacing.xs) {
                Text(formatted.value)
                    .font(Tokens.Font.readoutXL)
                    .lineLimit(1)
                    // "10.00" at the type-size cap would otherwise wrap in a narrow column.
                    .minimumScaleFactor(0.5)
                    .foregroundStyle(accentColor)
                    .monospacedDigit()
                    .shadow(color: accentColor.opacity(0.3), radius: 8)
                Text(formatted.unit)
                    .font(Tokens.Font.readoutLg)
                    .foregroundStyle(accentColor.opacity(0.7))
            }

            // Note name + cents
            Text(noteLabel)
                .font(Tokens.Font.readoutMd)
                .foregroundStyle(Tokens.Color.textSecondary)
                .monospacedDigit()
        }
        .accessibilityElement()
        .accessibilityLabel("Frequency")
        .accessibilityValue("\(formatted.value) \(formatted.unit), \(noteLabel)")
        .accessibilityIdentifier("frequencyReadout")
    }
}

#if DEBUG
    #Preview {
        VStack(alignment: .leading, spacing: 24) {
            FrequencyDisplay(frequencyHz: 440, accentColor: Tokens.Color.channelL)
            FrequencyDisplay(frequencyHz: 1000, accentColor: Tokens.Color.channelR)
            FrequencyDisplay(frequencyHz: 10000, accentColor: Tokens.Color.channelL)
        }
        .padding()
        .background(Tokens.Color.bg)
    }
#endif
