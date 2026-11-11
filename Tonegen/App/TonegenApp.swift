// Entry point — configures the audio session and injects the engine and store.
import AVFoundation
import os
import SwiftUI

@main
struct TonegenApp: App {
    private let engine: ToneEngine
    private let store: TonegenStore

    init() {
        Self.configureAudioSession()
        let eng = ToneEngine()
        engine = eng
        let st = TonegenStore(bridge: eng.bridge) {
            eng.ensureStarted()
        }
        store = st
        Self.observeAudioSession(engine: eng, store: st)
    }

    var body: some Scene {
        WindowGroup {
            ContentView(store: store, scopeL: engine.scopeL, scopeR: engine.scopeR)
        }
    }

    private static func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [])
            try session.setPreferredSampleRate(48000)
            try session.setPreferredIOBufferDuration(0.005)
        } catch {
            os_log(.error, "TonegenApp: Audio session configuration failed: %{public}@", error.localizedDescription)
        }
    }

    private static func observeAudioSession(engine: ToneEngine, store: TonegenStore) {
        let nc = NotificationCenter.default
        nc.addObserver(
            forName: AVAudioSession.interruptionNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { notification in
            handleInterruption(notification, engine: engine, store: store)
        }
        nc.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { notification in
            handleRouteChange(notification, store: store)
        }
    }

    private static func handleInterruption(
        _ notification: Notification,
        engine: ToneEngine,
        store: TonegenStore
    ) {
        guard let typeValue = notification.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else { return }
        switch type {
        case .began:
            break  // engine pauses automatically; keep store.playing = true so audio resumes
        case .ended:
            let optValue = notification.userInfo?[AVAudioSessionInterruptionOptionKey] as? UInt ?? 0
            if AVAudioSession.InterruptionOptions(rawValue: optValue).contains(.shouldResume), store.playing {
                engine.restart()
            }
        @unknown default:
            break
        }
    }

    private static func handleRouteChange(_ notification: Notification, store: TonegenStore) {
        guard let reasonValue = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: reasonValue),
              reason == .oldDeviceUnavailable else { return }
        store.setPlaying(false)
    }
}
