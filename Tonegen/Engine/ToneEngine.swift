// AVAudioEngine wrapper — lifecycle, session, and source node setup.
import AVFoundation
import os

final class ToneEngine {
    let bridge = ParamsBridge()

    var scopeL: SampleRingBuffer {
        renderer.scopeL
    }

    var scopeR: SampleRingBuffer {
        renderer.scopeR
    }

    private let engine = AVAudioEngine()
    private let renderer: ToneRenderer
    private let sourceNode: AVAudioSourceNode

    private var engineStarted = false

    init(sampleRate: Double = 48000) {
        guard let fmt = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        ) else {
            preconditionFailure("AVAudioFormat init failed for sampleRate=\(sampleRate)")
        }
        let rend = ToneRenderer(sampleRate: Float(sampleRate), bridge: bridge)
        let node = AVAudioSourceNode(format: fmt) { [rend] silence, _, frameCount, audioBufferList in
            rend.render(frames: Int(frameCount), buffers: audioBufferList, silence: silence)
            return noErr
        }
        renderer = rend
        sourceNode = node
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: fmt)
    }

    /// Starts the AVAudioEngine on first call; subsequent calls are no-ops.
    func ensureStarted() {
        guard !engineStarted else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setActive(true)
        } catch {
            os_log(.error, "ToneEngine: AVAudioSession.setActive failed: %{public}@", error.localizedDescription)
        }
        do { try engine.start() } catch { return }
        engineStarted = true
    }

    /// Resets engine state and restarts after an AVAudioSession interruption ends.
    func restart() {
        engineStarted = false
        ensureStarted()
    }
}
