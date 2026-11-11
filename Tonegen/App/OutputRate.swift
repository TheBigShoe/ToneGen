// Observable output sample rate shown in the header.
import AVFoundation
import Observation

/// Holds the hardware output sample rate so views read cached state instead of
/// querying `AVAudioSession` on every body evaluation.
///
/// Refreshed at launch and by the app whenever the route, engine configuration
/// or media services change.
@MainActor
@Observable
final class OutputRate {
    private(set) var sampleRate: Double

    init(sampleRate: Double = AVAudioSession.sharedInstance().sampleRate) {
        self.sampleRate = sampleRate
    }

    /// Re-reads the session's sample rate. Only assigns on change so observers
    /// are not invalidated needlessly.
    func refresh() {
        let current = AVAudioSession.sharedInstance().sampleRate
        if current != sampleRate { sampleRate = current }
    }

    /// Header text for a sample rate, e.g. "48 kHz · iOS".
    static func label(for sampleRate: Double) -> String {
        String(format: "%.0f kHz · iOS", sampleRate / 1000)
    }
}
