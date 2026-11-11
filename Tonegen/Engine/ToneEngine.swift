// AVAudioEngine wrapper — graph construction and output lifecycle.
import AVFoundation
import os

/// Owns the audio graph and decides when the hardware is running.
///
/// Output is live only between `start()` and `stop()`. Leaving the engine running
/// while silent would keep the app alive in the background and hold the audio
/// session away from other apps.
///
/// The graph generates at the hardware output rate so the main mixer never resamples
/// the test signal. The rate is re-read every time the hardware is (re)started — which
/// covers launch, configuration changes, media-services resets and a route change while
/// stopped — and the graph is reconnected if it moved.
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
    var onOutputLost: (@MainActor () -> Void)?

    /// Called after the graph moved to a new rate, with that rate in Hz.
    var onSampleRateChange: (@MainActor (Double) -> Void)?

    /// Rate the graph and renderer generate at, in Hz. Changes only between a hardware
    /// stop and the following start.
    private(set) var sampleRate: Double

    /// Rate used when neither the output node nor the session reports a usable one.
    nonisolated static let fallbackSampleRate: Double = 48000

    private var engine: AVAudioEngine
    private var sourceNode: AVAudioSourceNode
    private let renderer: ToneRenderer
    private var format: AVAudioFormat

    /// True while output is meant to be live. The system can stop the underlying
    /// engine without telling us, so this is intent, not hardware state.
    private var running = false

    /// Bumped by every start and stop so a delayed stop can tell it was superseded.
    private var transportGeneration = 0

    /// Long enough for the renderer's 5 ms mute envelope to reach silence before
    /// the hardware is stopped; cutting it sooner clicks.
    private static let fadeOutDuration: Duration = .milliseconds(80)

    init() {
        let eng = AVAudioEngine()
        var rate = Self.hardwareSampleRate(of: eng)
        var fmt = Self.makeFormat(sampleRate: rate)
        if fmt == nil {
            rate = Self.fallbackSampleRate
            fmt = Self.makeFormat(sampleRate: rate)
        }
        guard let fmt else {
            preconditionFailure("AVAudioFormat init failed for sampleRate=\(rate)")
        }
        let rend = ToneRenderer(sampleRate: Float(rate), bridge: bridge)
        sampleRate = rate
        format = fmt
        renderer = rend
        engine = eng
        sourceNode = Self.attachSource(renderer: rend, format: fmt, to: eng)

        // Not removed in deinit: the engine lives for the whole process.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            // Only the identity crosses into the main actor; the posting object itself
            // is not Sendable.
            let source = (notification.object as AnyObject?).map(ObjectIdentifier.init)
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
        let eng = AVAudioEngine()
        engine = eng
        sourceNode = Self.attachSource(renderer: renderer, format: format, to: eng)
        followHardwareRate()
    }

    /// Picks the rate to generate at: the output node's hardware format, else the
    /// session's rate, else 48 kHz. An output that is not yet configured can report 0.
    nonisolated static func resolveSampleRate(
        outputNodeRate: Double,
        sessionRate: Double
    ) -> Double {
        if outputNodeRate.isFinite, outputNodeRate > 0 { return outputNodeRate }
        if sessionRate.isFinite, sessionRate > 0 { return sessionRate }
        return fallbackSampleRate
    }

    // MARK: - Private

    private static func hardwareSampleRate(of engine: AVAudioEngine) -> Double {
        resolveSampleRate(
            outputNodeRate: engine.outputNode.outputFormat(forBus: 0).sampleRate,
            sessionRate: AVAudioSession.sharedInstance().sampleRate
        )
    }

    private static func makeFormat(sampleRate: Double) -> AVAudioFormat? {
        AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 2,
            interleaved: false
        )
    }

    /// Creates a source node rendering `format`, attaches it and connects it to the
    /// main mixer at that format. The mixer's output follows the hardware, so when the
    /// two rates match the signal reaches the output without resampling.
    ///
    /// `nonisolated` so the render block is not formed in a main-actor context. The SDK
    /// types the block as non-Sendable, so a closure built inside this `@MainActor` class
    /// would inherit main-actor isolation and Swift 6 would trap on its first call from
    /// the audio I/O thread. `@Sendable` makes the compiler prove it captures only the
    /// (Sendable) renderer.
    private nonisolated static func attachSource(
        renderer: ToneRenderer,
        format: AVAudioFormat,
        to engine: AVAudioEngine
    ) -> AVAudioSourceNode {
        let node = AVAudioSourceNode(format: format) { @Sendable silence, _, frameCount, buffers in
            renderer.render(frames: Int(frameCount), buffers: buffers, silence: silence)
            return noErr
        }
        engine.attach(node)
        engine.connect(node, to: engine.mainMixerNode, format: format)
        return node
    }

    /// Moves the graph and renderer to the current hardware output rate if it differs
    /// from the one they were built for. Call only while output is not meant to be live
    /// yet (immediately before `engine.start()`, or after a rebuild).
    ///
    /// Why this is safe against the render thread: `AVAudioEngine.stop()` is synchronous.
    /// When it returns the I/O unit has stopped, no render callback is executing, and
    /// none can begin until `engine.start()`, which runs later on this same main thread.
    /// `ToneRenderer.setSampleRate` therefore never overlaps `render`, so the render path
    /// needs no lock, atomic or flag for it. The source node is replaced rather than
    /// reconnected because its render format is fixed when it is created; the renderer
    /// (and with it `scopeL`/`scopeR`) and the `ParamsBridge` remain the same instances.
    private func followHardwareRate() {
        let rate = Self.hardwareSampleRate(of: engine)
        guard rate != sampleRate else { return }
        guard let newFormat = Self.makeFormat(sampleRate: rate) else {
            os_log(.error, "ToneEngine: no format for hardware rate %{public}f", rate)
            return
        }
        engine.stop()
        engine.disconnectNodeOutput(sourceNode)
        engine.detach(sourceNode)
        renderer.setSampleRate(Float(rate))
        format = newFormat
        sourceNode = Self.attachSource(renderer: renderer, format: newFormat, to: engine)
        sampleRate = rate
        onSampleRateChange?(rate)
    }

    private func startHardware() -> Bool {
        do {
            // Activate first: the session reports the route's real rate only while active.
            try AVAudioSession.sharedInstance().setActive(true)
            if !engine.isRunning {
                followHardwareRate()
                try engine.start()
            }
            return true
        } catch {
            Self.log("output start failed", error)
            return false
        }
    }

    /// The system stops the engine when the output hardware changes format
    /// (a USB interface or Bluetooth device with a different sample rate).
    /// The restart goes through `startHardware`, which moves the graph to the new rate.
    private func handleConfigurationChange(from source: ObjectIdentifier?) {
        guard source == ObjectIdentifier(engine), running else { return }
        if !startHardware() {
            running = false
            onOutputLost?()
        }
    }

    private static func log(_ message: String, _ error: Error) {
        os_log(.error, "ToneEngine: %{public}@: %{public}@", message, error.localizedDescription)
    }
}
