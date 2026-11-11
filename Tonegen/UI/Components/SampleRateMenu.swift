// Header control: shows the generator's real rate and lets the user request another.
import SwiftUI

/// A menu whose label is the rate the engine is actually generating at, with the
/// requested rate appended when the hardware is not honouring it. The checkmark marks
/// the request, never the actual rate: iOS may decline, and the label says so.
struct SampleRateMenu: View {
    let store: TonegenStore
    let outputRate: OutputRate

    var body: some View {
        Menu {
            ForEach(TonegenStore.allowedSampleRates, id: \.self) { rate in
                Button {
                    store.setRequestedSampleRate(rate)
                } label: {
                    if rate == store.requestedSampleRate {
                        Label("\(OutputRate.kilohertz(rate)) kHz", systemImage: "checkmark")
                    } else {
                        Text("\(OutputRate.kilohertz(rate)) kHz")
                    }
                }
            }
        } label: {
            Text(OutputRate.menuLabel(
                actual: outputRate.sampleRate,
                requested: store.requestedSampleRate
            ))
            .font(Tokens.Font.readoutXs)
            .foregroundStyle(Tokens.Color.textGhost)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .expandedHitArea(maxHorizontalGrowth: Tokens.Spacing.sm)
        }
        .accessibilityLabel("Output sample rate")
        .accessibilityValue(OutputRate.accessibilityValue(
            actual: outputRate.sampleRate,
            requested: store.requestedSampleRate
        ))
        .accessibilityIdentifier("sampleRateMenu")
    }
}
