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

    /// True when audio output could not be started or was lost and not recovered.
    /// Cleared by the next successful start.
    private(set) var outputFailed = false

    /// Brings audio output up. Returns false if the hardware could not be started.
    private let startOutput: () -> Bool
    /// Releases audio output after the renderer has faded out.
    private let stopOutput: () -> Void

    /// Set while an audio session interruption has paused playback the user started.
    private var resumeAfterInterruption = false

    init(
        bridge: ParamsBridge,
        startOutput: @escaping () -> Bool = { true },
        stopOutput: @escaping () -> Void = {}
    ) {
        self.bridge = bridge
        self.startOutput = startOutput
        self.stopOutput = stopOutput
        pushParams()
    }

    /// Starts or stops generation. If output cannot be started, `playing` stays
    /// false and `outputFailed` is set so the UI never claims to be generating
    /// while silent.
    func setPlaying(_ on: Bool) {
        resumeAfterInterruption = false
        guard on != playing else { return }
        if on {
            guard startOutput() else {
                outputFailed = true
                return
            }
            outputFailed = false
        } else {
            stopOutput()
        }
        playing = on
        pushParams()
    }

    /// An interruption (phone call, Siri, alarm) has silenced the app.
    func interruptionBegan() {
        guard playing else { return }
        setPlaying(false)
        resumeAfterInterruption = true
    }

    /// The interruption is over. Playback resumes only if the system says it may
    /// and the interruption — not the user — was what stopped it.
    func interruptionEnded(shouldResume: Bool) {
        guard resumeAfterInterruption else { return }
        resumeAfterInterruption = false
        if shouldResume { setPlaying(true) }
    }

    /// Output stopped underneath us and could not be restarted.
    func outputLost() {
        resumeAfterInterruption = false
        playing = false
        outputFailed = true
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
