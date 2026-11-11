// Single source of truth for all user-visible state.
import Foundation
import Observation
import UIKit

// Every mutator pushes an updated EngineParams snapshot through the bridge.

@Observable
@MainActor
final class TonegenStore {
    let bridge: ParamsBridge

    var left = ChannelState()
    var right = ChannelState()
    var masterGainDbfs: Double = 0
    var playing: Bool = false
    /// When true, an edit to either channel is mirrored to the other.
    /// Lives here (not in a view) so the compact tab layout and the wide two-column
    /// layout agree, and the setting survives a size-class change such as unfolding.
    var linked: Bool = true {
        didSet { if linked != oldValue { scheduleSave() } }
    }

    /// True when audio output could not be started or was lost and not recovered.
    /// Cleared by the next successful start.
    private(set) var outputFailed = false

    /// Brings audio output up. Returns false if the hardware could not be started.
    private let startOutput: @MainActor () -> Bool
    /// Releases audio output after the renderer has faded out.
    private let stopOutput: @MainActor () -> Void

    /// Set while an audio session interruption has paused playback the user started.
    private var resumeAfterInterruption = false

    /// Where settings persist; nil disables persistence.
    private let defaults: UserDefaults?
    private let saveDelay: Duration
    @ObservationIgnored private var pendingSave: Task<Void, Never>?
    // Only touched in init and deinit, hence safe to read from the nonisolated deinit.
    // swiftlint:disable:next modifier_order
    @ObservationIgnored private nonisolated(unsafe) var lifecycleObservers: [NSObjectProtocol] = []

    /// One versioned key; change the suffix together with `SettingsSnapshot.currentVersion`.
    static let settingsKey = "tonegen.settings.v1"

    init(
        bridge: ParamsBridge,
        startOutput: @escaping @MainActor () -> Bool = { true },
        stopOutput: @escaping @MainActor () -> Void = {},
        defaults: UserDefaults? = .standard,
        saveDelay: Duration = .milliseconds(500)
    ) {
        self.bridge = bridge
        self.startOutput = startOutput
        self.stopOutput = stopOutput
        self.defaults = defaults
        self.saveDelay = saveDelay
        // Restore before the first publish so the engine never sees stale defaults.
        restore()
        pushParams()
        observeLifecycle()
    }

    deinit {
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
    }

    /// Writes any pending change immediately. Called when the app leaves the
    /// foreground, since a debounced save could otherwise be lost on suspension.
    func flushSettings() {
        pendingSave?.cancel()
        pendingSave = nil
        saveNow()
    }

    /// Starts or stops generation. If output cannot be started, `playing` stays
    /// false and `outputFailed` is set so the UI never claims to be generating
    /// while silent.
    func setPlaying(_ on: Bool) {
        resumeAfterInterruption = false
        guard on != playing else { return }
        if on {
            guard startOutput() else {
                outputFailed = true
                return
            }
            outputFailed = false
        } else {
            stopOutput()
        }
        playing = on
        pushParams()
    }

    /// An interruption (phone call, Siri, alarm) has silenced the app.
    func interruptionBegan() {
        guard playing else { return }
        setPlaying(false)
        resumeAfterInterruption = true
    }

    /// The interruption is over. Playback resumes only if the system says it may
    /// and the interruption — not the user — was what stopped it.
    func interruptionEnded(shouldResume: Bool) {
        guard resumeAfterInterruption else { return }
        resumeAfterInterruption = false
        if shouldResume { setPlaying(true) }
    }

    /// Output stopped underneath us and could not be restarted.
    func outputLost() {
        resumeAfterInterruption = false
        playing = false
        outputFailed = true
        pushParams()
    }

    func setWaveform(_ waveform: Waveform, for side: ChannelSide) {
        applyToChannels(side) { $0.waveform = waveform }
        pushParams()
        scheduleSave()
    }

    func setFrequency(_ hz: Double, for side: ChannelSide) {
        applyToChannels(side) { $0.frequencyHz = hz }
        pushParams()
        scheduleSave()
    }

    func setAmplitude(_ dbfs: Double, for side: ChannelSide) {
        applyToChannels(side) { $0.amplitudeDbfs = dbfs }
        pushParams()
        scheduleSave()
    }

    func setPhase(_ fraction: Double, for side: ChannelSide) {
        applyToChannels(side) { $0.phaseFraction = fraction }
        pushParams()
        scheduleSave()
    }

    func setMuted(_ muted: Bool, for side: ChannelSide) {
        applyToChannels(side) { $0.muted = muted }
        pushParams()
        scheduleSave()
    }

    func setMasterGain(_ dbfs: Double) {
        masterGainDbfs = dbfs
        pushParams()
        scheduleSave()
    }

    // MARK: - Private

    private func restore() {
        guard let data = defaults?.data(forKey: Self.settingsKey),
              let snapshot = SettingsSnapshot.decode(data)
        else { return }
        left.apply(snapshot.left)
        right.apply(snapshot.right)
        masterGainDbfs = snapshot.masterGainDbfs
        linked = snapshot.linked
    }

    private func currentSnapshot() -> SettingsSnapshot {
        SettingsSnapshot(
            left: left.snapshot,
            right: right.snapshot,
            masterGainDbfs: masterGainDbfs,
            linked: linked
        )
    }

    private func saveNow() {
        guard let defaults, let data = SettingsSnapshot.encode(currentSnapshot()) else { return }
        defaults.set(data, forKey: Self.settingsKey)
    }

    /// Debounced so a slider drag costs one write, not one per tick.
    private func scheduleSave() {
        guard defaults != nil else { return }
        pendingSave?.cancel()
        let delay = saveDelay
        pendingSave = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            self?.flushSettings()
        }
    }

    private func observeLifecycle() {
        guard defaults != nil else { return }
        let center = NotificationCenter.default
        let names: [Notification.Name] = [
            UIApplication.willResignActiveNotification,
            UIApplication.didEnterBackgroundNotification
        ]
        lifecycleObservers = names.map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.flushSettings() }
            }
        }
    }

    private func applyToChannels(_ side: ChannelSide, _ mutate: (ChannelState) -> Void) {
        switch side {
        case .left:
            mutate(left)
            if linked { mutate(right) }
        case .right:
            mutate(right)
            if linked { mutate(left) }
        case .both:
            mutate(left)
            mutate(right)
        }
    }

    func pushParams() {
        bridge.update(
            EngineParams(
                left: left.engineChannel,
                right: right.engineChannel,
                masterGainDbfs: Float(masterGainDbfs),
                playing: playing
            )
        )
    }
}

enum ChannelSide { case left, right, both }

private extension ChannelState {
    var snapshot: SettingsSnapshot.Channel {
        SettingsSnapshot.Channel(
            frequencyHz: frequencyHz,
            amplitudeDbfs: amplitudeDbfs,
            phaseFraction: phaseFraction,
            waveform: waveform.rawValue,
            muted: muted
        )
    }

    func apply(_ s: SettingsSnapshot.Channel) {
        frequencyHz = s.frequencyHz
        amplitudeDbfs = s.amplitudeDbfs
        phaseFraction = s.phaseFraction
        waveform = Waveform(rawValue: s.waveform) ?? .sine
        muted = s.muted
    }

    var engineChannel: EngineParams.Channel {
        EngineParams.Channel(
            frequencyHz: Float(frequencyHz),
            amplitudeDbfs: Float(amplitudeDbfs),
            phaseFraction: Float(phaseFraction),
            waveform: waveform,
            muted: muted
        )
    }
}
