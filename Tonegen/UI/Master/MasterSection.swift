// Transport, master gain, and output level meters.
import SwiftUI

struct MasterSection: View {
    let store: TonegenStore
    let scopeL: SampleRingBuffer
    let scopeR: SampleRingBuffer
    /// Wide layout: show a Link/Unlink button in the header (no ChannelTabs there).
    var showLinkButton: Bool = false

    @State private var levelL: Float = 0
    @State private var levelR: Float = 0
    /// Reused every frame — avoids 60 allocs/s on the main thread.
    @State private var meterBuf = [Float](repeating: 0, count: readBlock)

    private static let frameInterval: Duration = .milliseconds(16)
    private static let frameSeconds: Float = 1.0 / 60
    /// Release speed after playback stops, in dB/s, so the bars fall instead of snapping to zero.
    private static let decayDbPerSec: Float = 60.0
    private static let readBlock = 512
    private static let meterFloorDb: Float = -60
    private static let meterHeight: CGFloat = 64

    private var masterBinding: Binding<Double> {
        Binding(
            get: { store.masterGainDbfs },
            set: { store.setMasterGain($0) }
        )
    }

    var body: some View {
        HStack(spacing: Tokens.Spacing.xl) {
            TransportButton(playing: store.playing) {
                store.setPlaying(!store.playing)
            }

            VStack(alignment: .leading, spacing: Tokens.Spacing.xs) {
                HStack {
                    Text("MASTER")
                        .font(Tokens.Font.label)
                        .tracking(2)
                        .foregroundStyle(Tokens.Color.textGhost)
                    if showLinkButton { linkButton }
                    Spacer()
                    Text(String(format: "%.1f dB", store.masterGainDbfs))
                        .font(Tokens.Font.readoutSm)
                        .foregroundStyle(Tokens.Color.textSecondary)
                        .monospacedDigit()
                }
                LinearSlider(
                    value: masterBinding,
                    range: -40 ... 0,
                    ticks: [-6, -12, -20, -30],
                    accentColor: Tokens.Color.linked,
                    label: "Master gain"
                )
            }

            HStack(spacing: Tokens.Spacing.xxs) {
                Meter(level: levelL, accentColor: Tokens.Color.channelL, label: "Left")
                Meter(level: levelR, accentColor: Tokens.Color.channelR, label: "Right")
            }
            .frame(height: Self.meterHeight)
        }
        // The meters are vertically greedy; without this the section swallows the
        // spare height in the wide layout and squeezes the channel columns.
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Tokens.Spacing.panelPadH)
        .padding(.vertical, Tokens.Spacing.panelPadV)
        // Re-keyed on `playing`: the loop only runs while audio is playing, plus the
        // short release tail, instead of waking the main run loop at 60 Hz forever.
        .task(id: store.playing) { await runMeters(playing: store.playing) }
    }

    // MARK: - Link button (wide layout only)

    private var linkButton: some View {
        Button {
            store.linked.toggle()
        } label: {
            HStack(spacing: Tokens.Spacing.xxs) {
                Image(systemName: store.linked ? "link" : "link.slash")
                    .font(.system(size: 10, weight: .medium))
                Text(store.linked ? "LINK" : "SPLIT")
                    .font(Tokens.Font.label)
                    .tracking(2)
            }
            .foregroundStyle(store.linked ? Tokens.Color.linked : Tokens.Color.textMuted)
            .padding(.horizontal, Tokens.Spacing.sm)
            .padding(.vertical, Tokens.Spacing.xxs)
            .background(
                RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                    .fill(store.linked ? Tokens.Color.panelActive : Tokens.Color.panel)
                    .overlay(
                        RoundedRectangle(cornerRadius: Tokens.Radius.chip)
                            .stroke(
                                store.linked ? Tokens.Color.linked.opacity(0.5) : Tokens.Color
                                    .stroke,
                                lineWidth: Tokens.Stroke.hairline
                            )
                    )
            )
            .expandedHitArea()
            .animation(.easeOut(duration: 0.15), value: store.linked)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.linked ? "Unlink channels" : "Link channels")
    }

    // MARK: - Meter computation

    /// Drives the meters until they have nothing left to show. While playing it never
    /// returns (the task is cancelled when `playing` changes); once stopped it ends as
    /// soon as both bars have fallen to zero.
    private func runMeters(playing: Bool) async {
        while !Task.isCancelled {
            if playing {
                levelL = measure(scopeL)
                levelR = measure(scopeR)
            } else {
                let fall = Self.decayDbPerSec / -Self.meterFloorDb * Self.frameSeconds
                levelL = max(0, levelL - fall)
                levelR = max(0, levelR - fall)
                if levelL == 0, levelR == 0 { return }
            }
            try? await Task.sleep(for: Self.frameInterval)
        }
    }

    /// RMS of the latest block, mapped to the meter's [0, 1] range.
    private func measure(_ scope: SampleRingBuffer) -> Float {
        let n = scope.readLatest(Self.readBlock, into: &meterBuf)
        guard n > 0 else { return 0 }
        var sumSquares: Float = 0
        for k in 0 ..< n {
            sumSquares += meterBuf[k] * meterBuf[k]
        }
        return Self.meterScale(sqrtf(sumSquares / Float(n)))
    }

    /// Maps a linear RMS amplitude to a [0, 1] meter position using a dB scale.
    /// meterFloorDb → 0, 0 dBFS → 1.
    private static func meterScale(_ linear: Float) -> Float {
        guard linear > 1e-7 else { return 0 }
        let db = 20 * log10f(linear)
        return max(0, min(1, (db - meterFloorDb) / -meterFloorDb))
    }
}

#if DEBUG
    #Preview {
        let engine = ToneEngine()
        let store = TonegenStore(bridge: engine.bridge)
        MasterSection(store: store, scopeL: engine.scopeL, scopeR: engine.scopeR)
            .background(Tokens.Color.bg)
    }
#endif
