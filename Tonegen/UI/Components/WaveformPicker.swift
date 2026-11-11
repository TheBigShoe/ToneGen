// Row of waveform chips — tap to select.
import SwiftUI

struct WaveformPicker: View {
    @Binding var selection: Waveform
    var accentColor: Color = Tokens.Color.channelL

    var body: some View {
        HStack(spacing: Tokens.Spacing.xs) {
            ForEach(Waveform.allCases) { wave in
                chip(wave)
            }
        }
    }

    private func chip(_ wave: Waveform) -> some View {
        let selected = wave == selection
        return Button {
            selection = wave
        } label: {
            VStack(spacing: 3) {
                WaveformGlyph(
                    waveform: wave,
                    color: selected ? accentColor : Tokens.Color.textMuted
                )
                Text(wave.label)
                    .font(Tokens.Font.label)
                    .tracking(1)
                    .foregroundStyle(selected ? accentColor : Tokens.Color.textMuted)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Tokens.Spacing.sm)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                    .fill(selected ? Tokens.Color.panelActive : Tokens.Color.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                            .stroke(
                                selected ? accentColor.opacity(0.6) : Tokens.Color.stroke,
                                lineWidth: Tokens.Stroke.hairline
                            )
                    )
            )
            .shadow(color: selected ? accentColor.opacity(0.2) : .clear, radius: 6)
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.15), value: selection)
        .accessibilityLabel(wave.accessibilityLabel)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

#if DEBUG
    #Preview {
        @Previewable @State var wave: Waveform = .sine
        WaveformPicker(selection: $wave)
            .padding()
            .background(Tokens.Color.bg)
    }
#endif
