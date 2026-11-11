// Full channel strip — waveform, frequency, amplitude, phase, mute.
import SwiftUI

struct ChannelView: View {
    let store: TonegenStore
    let active: ActiveChannel

    private var channel: ChannelState {
        active == .right ? store.right : store.left
    }

    private var side: ChannelSide {
        switch active {
        case .left: .left
        case .right: .right
        case .linked: .both
        }
    }

    private var accentColor: Color {
        switch active {
        case .left: Tokens.Color.channelL
        case .right: Tokens.Color.channelR
        case .linked: Tokens.Color.linked
        }
    }

    // MARK: - Bindings into the store

    private var freqBinding: Binding<Double> {
        Binding(
            get: { channel.frequencyHz },
            set: { store.setFrequency($0, for: side) }
        )
    }

    private var ampBinding: Binding<Double> {
        Binding(
            get: { channel.amplitudeDbfs },
            set: { store.setAmplitude($0, for: side) }
        )
    }

    private var phaseBinding: Binding<Double> {
        Binding(
            get: { channel.phaseFraction },
            set: { store.setPhase($0, for: side) }
        )
    }

    private var waveformBinding: Binding<Waveform> {
        Binding(
            get: { channel.waveform },
            set: { store.setWaveform($0, for: side) }
        )
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Waveform picker
            sectionHeader("WAVEFORM")
            WaveformPicker(selection: waveformBinding, accentColor: accentColor)
                .padding(.horizontal, Tokens.Spacing.panelPadH)
                .padding(.top, Tokens.Spacing.sm)
                .padding(.bottom, Tokens.Spacing.xl)

            // Frequency display + slider + presets
            FrequencyDisplay(frequencyHz: channel.frequencyHz, accentColor: accentColor)
                .padding(.horizontal, Tokens.Spacing.panelPadH)
                .padding(.bottom, Tokens.Spacing.md)

            FreqSlider(frequencyHz: freqBinding, accentColor: accentColor)
                .padding(.horizontal, Tokens.Spacing.panelPadH)

            PresetRow(frequencyHz: freqBinding, accentColor: accentColor)
                .padding(.horizontal, Tokens.Spacing.panelPadH)
                .padding(.top, Tokens.Spacing.sm)
                .padding(.bottom, Tokens.Spacing.xl)

            // Amplitude
            sliderRow(
                label: "AMPLITUDE",
                value: String(format: "%.1f dBFS", channel.amplitudeDbfs),
                accentColor: accentColor
            ) {
                LinearSlider(
                    value: ampBinding,
                    range: -60 ... 0,
                    ticks: [-12, -24, -36, -48],
                    accentColor: accentColor,
                    label: "Amplitude"
                )
            }

            // Phase
            sliderRow(
                label: "PHASE",
                value: phaseLabel,
                accentColor: accentColor
            ) {
                LinearSlider(
                    value: phaseBinding,
                    range: 0 ... 1,
                    accentColor: accentColor,
                    label: "Phase"
                )
            }

            // Mute
            muteRow
                .padding(.horizontal, Tokens.Spacing.panelPadH)
                .padding(.vertical, Tokens.Spacing.md)
        }
    }

    // MARK: - Sub-views

    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(Tokens.Font.label)
            .tracking(2)
            .foregroundStyle(Tokens.Color.textGhost)
            .padding(.horizontal, Tokens.Spacing.panelPadH)
            .padding(.top, Tokens.Spacing.panelPadV)
    }

    private func sliderRow(
        label: String,
        value: String,
        accentColor _: Color,
        @ViewBuilder slider: () -> some View
    ) -> some View {
        VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
            HStack {
                Text(label)
                    .font(Tokens.Font.label)
                    .tracking(2)
                    .foregroundStyle(Tokens.Color.textGhost)
                Spacer()
                Text(value)
                    .font(Tokens.Font.readoutSm)
                    .foregroundStyle(Tokens.Color.textSecondary)
                    .monospacedDigit()
            }
            slider()
        }
        .padding(.horizontal, Tokens.Spacing.panelPadH)
        .padding(.bottom, Tokens.Spacing.xl)
    }

    private var phaseLabel: String {
        let degrees = Int(channel.phaseFraction * 360)
        return "\(degrees)°"
    }

    private var muteRow: some View {
        HStack(spacing: Tokens.Spacing.md) {
            muteButton
            Spacer()
        }
    }

    private var muteButton: some View {
        let muted = channel.muted
        return Button {
            store.setMuted(!muted, for: side)
        } label: {
            HStack(spacing: Tokens.Spacing.xs) {
                Image(systemName: muted ? "speaker.slash.fill" : "speaker.fill")
                    .font(.system(size: 12, weight: .medium))
                Text(muted ? "MUTED" : "MUTE")
                    .font(Tokens.Font.label)
                    .tracking(2)
            }
            .foregroundStyle(muted ? Tokens.Color.meterHot : Tokens.Color.textSecondary)
            .padding(.horizontal, Tokens.Spacing.md)
            .padding(.vertical, Tokens.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                    .fill(muted ? Tokens.Color.meterHot.opacity(0.15) : Tokens.Color.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                            .stroke(
                                muted ? Tokens.Color.meterHot.opacity(0.5) : Tokens.Color.stroke,
                                lineWidth: Tokens.Stroke.hairline
                            )
                    )
            )
            .expandedHitArea()
            .animation(.easeOut(duration: 0.2), value: muted)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(muted ? "Unmute channel" : "Mute channel")
    }
}

#if DEBUG
    #Preview {
        let engine = ToneEngine()
        let store = TonegenStore(bridge: engine.bridge)
        ScrollView {
            ChannelView(store: store, active: .left)
                .background(Tokens.Color.bg)
        }
        .background(Tokens.Color.bg)
    }
#endif
