// Flat, Sendable snapshot of all UI-controllable parameters.
// Written on the main thread via ParamsBridge; read on the audio render thread.

// swiftformat:disable redundantSendable
// Declared explicitly (though internal structs infer it) so the audio-thread contract is checked.
struct EngineParams: Sendable {
    struct Channel: Sendable {
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

// swiftformat:enable redundantSendable
