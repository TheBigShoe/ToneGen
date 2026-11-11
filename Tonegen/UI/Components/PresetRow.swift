// Octave / semitone nudge buttons and frequency preset chips.
import SwiftUI

private let presets: [(String, Double)] = [
    ("100", 100), ("440", 440), ("1k", 1000), ("10k", 10000)
]
private let semitoneUp = pow(2, 1.0 / 12)
private let semitoneDown = pow(2, -1.0 / 12)

struct PresetRow: View {
    @Binding var frequencyHz: Double
    var accentColor: Color = Tokens.Color.channelL

    var body: some View {
        HStack(spacing: Tokens.Spacing.xs) {
            nudgeButton("-OCT") { frequencyHz = clampFreq(frequencyHz / 2) }
            nudgeButton("-ST") { frequencyHz = clampFreq(frequencyHz * semitoneDown) }

            ForEach(presets, id: \.1) { label, freq in
                presetChip(label: label, freq: freq)
            }

            nudgeButton("+ST") { frequencyHz = clampFreq(frequencyHz * semitoneUp) }
            nudgeButton("+OCT") { frequencyHz = clampFreq(frequencyHz * 2) }
        }
    }

    // MARK: - Nudge button with press-and-hold repeat at 4 Hz

    private func nudgeButton(_ label: String, action: @escaping () -> Void) -> some View {
        RepeatButton(label: label, accentColor: accentColor, action: action)
    }

    // MARK: - Preset chip

    private func presetChip(label: String, freq: Double) -> some View {
        let active = abs(frequencyHz - freq) < 0.5
        return Button {
            frequencyHz = freq
        } label: {
            Text(label)
                .font(Tokens.Font.label)
                .tracking(1)
                .foregroundStyle(active ? accentColor : Tokens.Color.textMuted)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Tokens.Spacing.xs)
                .background(
                    RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                        .fill(active ? Tokens.Color.panelActive : Tokens.Color.panel)
                        .overlay(
                            RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                                .stroke(
                                    active ? accentColor.opacity(0.5) : Tokens.Color.stroke,
                                    lineWidth: Tokens.Stroke.hairline
                                )
                        )
                )
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.impact(weight: .light), trigger: active)
    }
}

// MARK: - RepeatButton — fires immediately and then repeats at 4 Hz on hold

private struct RepeatButton: View {
    let label: String
    var accentColor: Color
    let action: () -> Void

    @State private var timer: Timer?

    var body: some View {
        Text(label)
            .font(Tokens.Font.label)
            .tracking(1)
            .foregroundStyle(Tokens.Color.textSecondary)
            // Narrow columns (two-up on a 669 pt foldable) must not wrap "-OCT".
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, Tokens.Spacing.xs)
            .padding(.vertical, Tokens.Spacing.xs)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                    .fill(Tokens.Color.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                            .stroke(Tokens.Color.stroke, lineWidth: Tokens.Stroke.hairline)
                    )
            )
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in startIfNeeded() }
                    .onEnded { _ in stopTimer() }
            )
            // A view removed mid-press never receives the drag's onEnded, which would
            // leave the repeat timer firing against a dead view.
            .onDisappear { stopTimer() }
    }

    private func startIfNeeded() {
        guard timer == nil else { return }
        action()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { _ in action() }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

// MARK: - Helpers

private func clampFreq(_ f: Double) -> Double {
    min(max(f, 20), 20000)
}

#if DEBUG
    #Preview {
        @Previewable @State var freq: Double = 440
        VStack(spacing: 16) {
            PresetRow(frequencyHz: $freq)
            Text(String(format: "%.2f Hz", freq))
                .font(Tokens.Font.readoutMd)
                .foregroundStyle(Tokens.Color.channelL)
        }
        .padding()
        .background(Tokens.Color.bg)
    }
#endif
