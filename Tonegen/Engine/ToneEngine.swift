// AVAudioEngine wrapper — graph construction and output lifecycle.
import AVFoundation
import os

/// Owns the audio graph and decides when the hardware is running.
///
/// Output is live only between `start()` and `stop()`. Leaving the engine running
/// while silent would keep the app alive in the background and hold the audio
/// session away from other apps.
@MainActor
final class ToneEngine {
    let bridge = ParamsBridge()

    var scopeL: SampleRingBuffer {
        renderer.scopeL
    }

    var scopeR: SampleRingBuffer {
        renderer.scopeR
    }

    /// Called when output was live and could not be brought back after the system
    /// stopped the engine (for example a hardware change that failed to restart).
    var onOutputLost: (() -> Void)?

    private var engine: AVAudioEngine
    private let renderer: ToneRenderer
    private let format: AVAudioFormat

    /// True while output is meant to be live. The system can stop the underlying
    /// engine without telling us, so this is intent, not hardware state.
    private var running = false

    /// Bumped by every start and stop so a delayed stop can tell it was superseded.
    private var transportGeneration = 0

    /// Long enough for the renderer's 5 ms mute envelope to reach silence before
    /// the hardware is stopped; cutting it sooner clicks.
    private static let fadeOutDuration: Duration = .milliseconds(80)

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
        format = fmt
        renderer = rend
        engine = Self.makeGraph(renderer: rend, format: fmt)

        // Not removed in deinit: the engine lives for the whole process.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let source = notification.object as AnyObject?
            MainActor.assumeIsolated {
                self?.handleConfigurationChange(from: source)
            }
        }
    }

    /// Activates the audio session and starts the hardware.
    /// - Returns: `false` if output could not be started; the reason is logged.
    @discardableResult
    func start() -> Bool {
        transportGeneration &+= 1
        guard startHardware() else {
            running = false
            return false
        }
        running = true
        return true
    }

    /// Stops the hardware and releases the audio session once the renderer has
    /// faded out. A `start()` before the fade completes cancels the stop.
    func stop() {
        guard running else { return }
        running = false
        transportGeneration &+= 1
        let generation = transportGeneration
        Task { [weak self] in
            try? await Task.sleep(for: Self.fadeOutDuration)
            guard let self, transportGeneration == generation else { return }
            engine.stop()
            do {
                try AVAudioSession.sharedInstance()
                    .setActive(false, options: .notifyOthersOnDeactivation)
            } catch {
                Self.log("session deactivation failed", error)
            }
        }
    }

    /// Brings the hardware back if playback is intended but the underlying engine
    /// is no longer running (a route change can stop it without a configuration
    /// change notification). Never starts audio the user had stopped.
    /// - Returns: `true` if output is live or was not wanted; `false` if the
    ///   restart failed.
    @discardableResult
    func ensureRunning() -> Bool {
        guard running else { return true }
        if engine.isRunning { return true }
        if startHardware() { return true }
        running = false
        return false
    }

    /// Call when an audio session interruption begins. The system has already
    /// silenced us; this records that and leaves the session alone so the
    /// matching interruption-ended notification still arrives.
    func suspendForInterruption() {
        running = false
        transportGeneration &+= 1
        engine.stop()
    }

    /// Discards the audio graph and builds a fresh one. Required after a media
    /// services reset, which invalidates every existing audio object.
    /// Output is stopped afterwards; call `start()` to resume.
    func rebuild() {
        running = false
        transportGeneration &+= 1
        engine.stop()
        engine = Self.makeGraph(renderer: renderer, format: format)
    }

    // MARK: - Private

    private static func makeGraph(renderer: ToneRenderer, format: AVAudioFormat) -> AVAudioEngine {
        let engine = AVAudioEngine()
        let node = AVAudioSourceNode(format: format) { silence, _, frameCount, audioBufferList in
            renderer.render(frames: Int(frameCount), buffers: audioBufferList, silence: silence)
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        return engine
    }

    private func startHardware() -> Bool {
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            if !engine.isRunning { try engine.start() }
            return true
        } catch {
            Self.log("output start failed", error)
            return false
        }
    }

    /// The system stops the engine when the output hardware changes format
    /// (a USB interface or Bluetooth device with a different sample rate).
    /// The graph reconnects to the new hardware format on the next start.
    private func handleConfigurationChange(from source: AnyObject?) {
        guard source === engine, running else { return }
        if !startHardware() {
            running = false
            onOutputLost?()
        }
    }

    private static func log(_ message: String, _ error: Error) {
        os_log(.error, "ToneEngine: %{public}@: %{public}@", message, error.localizedDescription)
    }
}
