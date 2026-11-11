// Flat, Sendable snapshot of all UI-controllable parameters.
// Written on the main thread via ParamsBridge; read on the audio render thread.

struct EngineParams {
    struct Channel {
        var frequencyHz: Float = 440
        var amplitudeDbfs: Float = -12
        var phaseFraction: Float = 0
        var waveform: Waveform = .sine
        var muted: Bool = false
    }

    var left: Channel = .init()
    var right: Channel = .init()
    var masterGainDbfs: Float = 0
    var playing: Bool = false
}
