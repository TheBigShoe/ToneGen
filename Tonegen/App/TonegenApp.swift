// Entry point — configures the audio session and injects the engine and store.
import AVFoundation
import os
import SwiftUI

@main
struct TonegenApp: App {
    private let engine: ToneEngine
    private let store: TonegenStore
    private let outputRate: OutputRate
    private let nowPlaying: NowPlayingController

    init() {
        // Read straight from defaults: the store needs the engine, which needs the session
        // configured first.
        Self.configureAudioSession(sampleRate: TonegenStore.savedSampleRate())
        let eng = ToneEngine()
        engine = eng
        let st = TonegenStore(
            bridge: eng.bridge,
            startOutput: { eng.start() },
            stopOutput: { eng.stop() },
            applySampleRate: { rate in
                Self.setPreferredSampleRate(rate)
                eng.followPreferredRateChange()
            }
        )
        eng.onOutputLost = { [weak st] in st?.outputLost() }
        store = st
        // The header shows the engine's render rate, which changes only when the engine
        // moves its graph — not the session rate, which can lead it while stopped.
        let rate = OutputRate(sampleRate: eng.sampleRate)
        outputRate = rate
        eng.onSampleRateChange = { [weak rate] in rate?.update($0) }
        nowPlaying = NowPlayingController(store: st)
        Self.observeAudioSession(engine: eng, store: st)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                store: store,
                scopeL: engine.scopeL,
                scopeR: engine.scopeR,
                outputRate: outputRate
            )
            // Keeps lock-screen state in step however playing changed (UI, remote
            // command, interruption or output loss).
            .onChange(of: store.playing) { nowPlaying.refresh() }
        }
    }

    /// Configures the session. `sampleRate` is a request; the route may run at another.
    private static func configureAudioSession(sampleRate: Double) {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setPreferredSampleRate(sampleRate)
            try session.setPreferredIOBufferDuration(0.005)
        } catch {
            os_log(
                .error,
                "TonegenApp: Audio session configuration failed: %{public}@",
                error.localizedDescription
            )
        }
    }

    /// Updates only the preference; the session is not activated here, so a stopped
    /// app does not take the audio route just to change a setting.
    @MainActor
    private static func setPreferredSampleRate(_ rate: Double) {
        do {
            try AVAudioSession.sharedInstance().setPreferredSampleRate(rate)
        } catch {
            os_log(
                .error,
                "TonegenApp: Setting preferred sample rate failed: %{public}@",
                error.localizedDescription
            )
        }
    }

    private static func observeAudioSession(engine: ToneEngine, store: TonegenStore) {
        let nc = NotificationCenter.default
        let session = AVAudioSession.sharedInstance()
        nc.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: session,
            queue: .main
        ) { notification in
            let info = InterruptionInfo(notification)
            MainActor.assumeIsolated {
                handleInterruption(info, engine: engine, store: store)
            }
        }
        nc.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: session,
            queue: .main
        ) { notification in
            let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            MainActor.assumeIsolated {
                handleRouteChange(reason: raw, engine: engine, store: store)
            }
        }
        nc.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: session,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                handleMediaServicesReset(engine: engine, store: store)
            }
        }
    }

    /// The parts of an interruption notification we act on, extracted so the
    /// non-Sendable `Notification` never crosses into the main-actor closure.
    private struct InterruptionInfo {
        let type: AVAudioSession.InterruptionType?
        let shouldResume: Bool

        init(_ notification: Notification) {
            let info = notification.userInfo
            type = (info?[AVAudioSessionInterruptionTypeKey] as? UInt)
                .flatMap(AVAudioSession.InterruptionType.init(rawValue:))
            let options = info?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            shouldResume = AVAudioSession.InterruptionOptions(rawValue: options)
                .contains(.shouldResume)
        }
    }

    @MainActor
    private static func handleInterruption(
        _ info: InterruptionInfo,
        engine: ToneEngine,
        store: TonegenStore
    ) {
        guard let type = info.type else { return }
        switch type {
        case .began:
            // Engine first: it must not deactivate the session during an
            // interruption, which the store's normal stop path would do.
            engine.suspendForInterruption()
            store.interruptionBegan()
        case .ended:
            store.interruptionEnded(shouldResume: info.shouldResume)
        @unknown default:
            break
        }
    }

    @MainActor
    private static func handleRouteChange(
        reason raw: UInt?,
        engine: ToneEngine,
        store: TonegenStore
    ) {
        guard let raw, let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        switch reason {
        case .oldDeviceUnavailable:
            // Headphones unplugged: stop rather than blast the tone out of the speaker.
            store.setPlaying(false)
        case .newDeviceAvailable, .override, .categoryChange, .routeConfigurationChange,
             .wakeFromSleep:
            // The system can stop the engine on these without a configuration-change
            // notification, which would leave the UI claiming to generate in silence.
            guard store.playing else { return }
            if !engine.ensureRunning() { store.outputLost() }
        default:
            break
        }
    }

    /// The media server crashed and restarted: every audio object is dead and the
    /// session has lost its configuration.
    @MainActor
    private static func handleMediaServicesReset(engine: ToneEngine, store: TonegenStore) {
        let wasPlaying = store.playing
        configureAudioSession(sampleRate: store.requestedSampleRate)
        engine.rebuild()
        guard wasPlaying else { return }
        if !engine.start() { store.outputLost() }
    }
}
