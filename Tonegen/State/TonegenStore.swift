// Single source of truth for all user-visible state.
import Observation

// Every mutator pushes an updated EngineParams snapshot through the bridge.

@Observable
@MainActor
final class TonegenStore {
    let bridge: ParamsBridge

    var left = ChannelState()
    var right = ChannelState()
    var masterGainDbfs: Double = 0
    var playing: Bool = false
    /// When true, an edit to either channel is mirrored to the other.
    /// Lives here (not in a view) so the compact tab layout and the wide two-column
    /// layout agree, and the setting survives a size-class change such as unfolding.
    var linked: Bool = true

    /// Called when the playing state transitions from false → true (use to start the engine).
    private let onFirstPlay: () -> Void

    init(bridge: ParamsBridge, onFirstPlay: @escaping () -> Void = {}) {
        self.bridge = bridge
        self.onFirstPlay = onFirstPlay
        pushParams()
    }

    func setPlaying(_ on: Bool) {
        let wasPlaying = playing
        playing = on
        if on, !wasPlaying { onFirstPlay() }
        pushParams()
    }

    func setWaveform(_ waveform: Waveform, for side: ChannelSide) {
        applyToChannels(side) { $0.waveform = waveform }
        pushParams()
    }

    func setFrequency(_ hz: Double, for side: ChannelSide) {
        applyToChannels(side) { $0.frequencyHz = hz }
        pushParams()
    }

    func setAmplitude(_ dbfs: Double, for side: ChannelSide) {
        applyToChannels(side) { $0.amplitudeDbfs = dbfs }
        pushParams()
    }

    func setPhase(_ fraction: Double, for side: ChannelSide) {
        applyToChannels(side) { $0.phaseFraction = fraction }
        pushParams()
    }

    func setMuted(_ muted: Bool, for side: ChannelSide) {
        applyToChannels(side) { $0.muted = muted }
        pushParams()
    }

    func setMasterGain(_ dbfs: Double) {
        masterGainDbfs = dbfs
        pushParams()
    }

    // MARK: - Private

    private func applyToChannels(_ side: ChannelSide, _ mutate: (ChannelState) -> Void) {
        switch side {
        case .left:
            mutate(left)
            if linked { mutate(right) }
        case .right:
            mutate(right)
            if linked { mutate(left) }
        case .both:
            mutate(left)
            mutate(right)
        }
    }

    func pushParams() {
        bridge.update(
            EngineParams(
                left: left.engineChannel,
                right: right.engineChannel,
                masterGainDbfs: Float(masterGainDbfs),
                playing: playing
            )
        )
    }
}

enum ChannelSide { case left, right, both }

private extension ChannelState {
    var engineChannel: EngineParams.Channel {
        EngineParams.Channel(
            frequencyHz: Float(frequencyHz),
            amplitudeDbfs: Float(amplitudeDbfs),
            phaseFraction: Float(phaseFraction),
            waveform: waveform,
            muted: muted
        )
    }
}
