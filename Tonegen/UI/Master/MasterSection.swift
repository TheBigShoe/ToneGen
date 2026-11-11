// Transport, master gain, and output level meters.
import Combine
import SwiftUI

struct MasterSection: View {
    let store: TonegenStore
    let scopeL: SampleRingBuffer
    let scopeR: SampleRingBuffer
    /// Wide layout: show a Link/Unlink button in the header (no ChannelTabs there).
    var showLinkButton: Bool = false

    @State private var peakL: Float = 0
    @State private var peakR: Float = 0
    @State private var holdL: Float = 0
    @State private var holdR: Float = 0
    @State private var holdAgeL: Double = 0
    @State private var holdAgeR: Double = 0
    /// Reused every frame — avoids 60 allocs/s on the main thread.
    @State private var meterBuf = [Float](repeating: 0, count: readBlock)

    private static let holdDuration: Double = 1.0
    private static let decayDbPerSec: Float = 20.0
    private static let readBlock = 512
    private static let meterFloorDb: Float = -60
    private static let meterHeight: CGFloat = 64

    /// 60 Hz timer drives meter updates off the main run loop (avoids let _ = in ViewBuilder).
    private let displayTimer = Timer.publish(every: 1.0 / 60, on: .main, in: .common).autoconnect()

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
                Meter(level: peakL, accentColor: Tokens.Color.channelL)
                Meter(level: peakR, accentColor: Tokens.Color.channelR)
            }
            .frame(height: Self.meterHeight)
        }
        // The meters are vertically greedy; without this the section swallows the
        // spare height in the wide layout and squeezes the channel columns.
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, Tokens.Spacing.panelPadH)
        .padding(.vertical, Tokens.Spacing.panelPadV)
        .onReceive(displayTimer) { date in
            guard store.playing else { return }
            updateMeters(time: date.timeIntervalSinceReferenceDate)
        }
        .onChange(of: store.playing) { _, isPlaying in
            if !isPlaying { peakL = 0; peakR = 0; holdL = 0; holdR = 0; holdAgeL = 0; holdAgeR = 0 }
        }
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
            .animation(.easeOut(duration: 0.15), value: store.linked)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.linked ? "Unlink channels" : "Link channels")
    }

    // MARK: - Meter computation

    private func updateMeters(time: Double) {
        updateChannel(
            scope: scopeL,
            buf: &meterBuf,
            time: time,
            peak: &peakL,
            hold: &holdL,
            holdAge: &holdAgeL
        )
        updateChannel(
            scope: scopeR,
            buf: &meterBuf,
            time: time,
            peak: &peakR,
            hold: &holdR,
            holdAge: &holdAgeR
        )
    }

    private func updateChannel(
        scope: SampleRingBuffer,
        buf: inout [Float],
        time: Double,
        peak: inout Float,
        hold: inout Float,
        holdAge: inout Double
    ) {
        let n = scope.readLatest(Self.readBlock, into: &buf)
        guard n > 0 else {
            peak = 0; hold = 0; holdAge = 0
            return
        }
        var rms: Float = 0
        for k in 0 ..< n {
            rms += buf[k] * buf[k]
        }
        rms = sqrtf(rms / Float(n))
        let scaled = Self.meterScale(rms)
        peak = scaled

        let dt = Float(1.0 / 60)
        if scaled >= hold {
            hold = scaled
            holdAge = time
        } else if time - holdAge > Self.holdDuration {
            hold = max(hold - Self.decayDbPerSec / (-Self.meterFloorDb) * dt, scaled)
        }
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
