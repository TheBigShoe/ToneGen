// Entry point — configures the audio session and injects the engine and store.
import AVFoundation
import os
import SwiftUI

@main
struct TonegenApp: App {
    private let engine: ToneEngine
    private let store: TonegenStore
    private let outputRate: OutputRate

    init() {
        Self.configureAudioSession()
        let eng = ToneEngine()
        engine = eng
        let st = TonegenStore(
            bridge: eng.bridge,
            startOutput: { eng.start() },
            stopOutput: { eng.stop() }
        )
        eng.onOutputLost = { [weak st] in st?.outputLost() }
        store = st
        let rate = OutputRate()
        outputRate = rate
        // Engine config changes (e.g. a new hardware rate) can arrive without a route change.
        NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: nil,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated { rate.refresh() }
        }
        Self.observeAudioSession(engine: eng, store: st, outputRate: rate)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(
                store: store,
                scopeL: engine.scopeL,
                scopeR: engine.scopeR,
                outputRate: outputRate
            )
        }
    }

    private static func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setPreferredSampleRate(48000)
            try session.setPreferredIOBufferDuration(0.005)
        } catch {
            os_log(
                .error,
                "TonegenApp: Audio session configuration failed: %{public}@",
                error.localizedDescription
            )
        }
    }

    private static func observeAudioSession(
        engine: ToneEngine,
        store: TonegenStore,
        outputRate: OutputRate
    ) {
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
                handleRouteChange(reason: raw, store: store, outputRate: outputRate)
            }
        }
        nc.addObserver(
            forName: AVAudioSession.mediaServicesWereResetNotification,
            object: session,
            queue: .main
        ) { _ in
            MainActor.assumeIsolated {
                handleMediaServicesReset(engine: engine, store: store, outputRate: outputRate)
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
        store: TonegenStore,
        outputRate: OutputRate
    ) {
        outputRate.refresh()
        // Headphones unplugged: stop rather than blast the tone out of the speaker.
        guard let raw,
              AVAudioSession.RouteChangeReason(rawValue: raw) == .oldDeviceUnavailable
        else { return }
        store.setPlaying(false)
    }

    /// The media server crashed and restarted: every audio object is dead and the
    /// session has lost its configuration.
    @MainActor
    private static func handleMediaServicesReset(
        engine: ToneEngine,
        store: TonegenStore,
        outputRate: OutputRate
    ) {
        let wasPlaying = store.playing
        configureAudioSession()
        engine.rebuild()
        outputRate.refresh()
        guard wasPlaying else { return }
        if !engine.start() { store.outputLost() }
    }
}
