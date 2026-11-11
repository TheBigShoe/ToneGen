// Observable per-channel parameters for the UI layer.
import Observation

@Observable
final class ChannelState {
    var frequencyHz: Double = 440
    var amplitudeDbfs: Double = -12
    var phaseFraction: Double = 0
    var waveform: Waveform = .sine
    var muted: Bool = false
}
