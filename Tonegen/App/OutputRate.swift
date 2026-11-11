// Observable generator sample rate shown in the header.
import Foundation
import Observation

/// Holds the rate the tone engine is generating at, so the header shows what is
/// actually produced rather than what the session reports.
///
/// The app seeds it from `ToneEngine.sampleRate` and updates it from
/// `ToneEngine.onSampleRateChange`. The session rate can move (a route change while
/// stopped) before the engine follows it on the next start; reading the engine keeps
/// the label and the signal in agreement.
@MainActor
@Observable
final class OutputRate {
    private(set) var sampleRate: Double

    init(sampleRate: Double = ToneEngine.fallbackSampleRate) {
        self.sampleRate = sampleRate
    }

    /// Records a new generator rate. Only assigns on change so observers are not
    /// invalidated needlessly.
    func update(_ rate: Double) {
        if rate != sampleRate { sampleRate = rate }
    }

    /// Header text for a sample rate, e.g. "48 kHz · iOS" or "44.1 kHz · iOS".
    static func label(for sampleRate: Double) -> String {
        "\(kilohertz(sampleRate)) kHz · iOS"
    }

    /// Header menu label. Shows the actual rate; when the hardware is not running the
    /// requested one, appends it ("48 kHz · 96 req") so the request is never mistaken
    /// for the rate in use.
    static func menuLabel(actual: Double, requested: Double) -> String {
        guard actual != requested else { return label(for: actual) }
        return "\(kilohertz(actual)) kHz · \(kilohertz(requested)) req"
    }

    /// VoiceOver value: the actual rate, plus the request when it differs.
    static func accessibilityValue(actual: Double, requested: Double) -> String {
        guard actual != requested else { return "\(kilohertz(actual)) kHz" }
        return "\(kilohertz(actual)) kHz, \(kilohertz(requested)) kHz requested"
    }

    /// Rate in kHz with up to two decimals and no trailing zeros: 48000 → "48",
    /// 44100 → "44.1", 22050 → "22.05". Fixed "." separator — this is a spec value.
    static func kilohertz(_ sampleRate: Double) -> String {
        var text = String(format: "%.2f", sampleRate / 1000)
        while text.hasSuffix("0") {
            text.removeLast()
        }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }
}
