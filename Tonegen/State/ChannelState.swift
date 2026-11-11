// Per-channel parameters for the UI layer.

/// A value type so the store's channels can only change through `TonegenStore`, and so
/// it is `Sendable` without any isolation of its own. Observation happens through the
/// store's `left` / `right` properties.
struct ChannelState: Equatable {
    var frequencyHz: Double = 440
    var amplitudeDbfs: Double = -12
    var phaseFraction: Double = 0
    var waveform: Waveform = .sine
    var muted: Bool = false
}
