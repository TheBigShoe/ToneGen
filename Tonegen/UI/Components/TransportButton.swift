// Large amber play/pause transport button.
import SwiftUI

struct TransportButton: View {
    let playing: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: playing ? "pause.fill" : "play.fill")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(playing ? Tokens.Color.bg : Tokens.Color.bg)
                .frame(width: 52, height: 52)
                .background(
                    Circle()
                        .fill(playing ? Tokens.Color.meterHot : Tokens.Color.channelL)
                        .shadow(
                            color: (playing ? Tokens.Color.meterHot : Tokens.Color.channelL)
                                .opacity(0.5),
                            radius: 10
                        )
                )
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.2), value: playing)
        .accessibilityLabel(playing ? "Pause" : "Play")
    }
}

#if DEBUG
    #Preview {
        @Previewable @State var playing = false
        TransportButton(playing: playing) { playing.toggle() }
            .padding()
            .background(Tokens.Color.bg)
    }
#endif
