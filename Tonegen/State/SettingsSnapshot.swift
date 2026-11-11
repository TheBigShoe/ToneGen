// Codable, versioned image of the user's settings for UserDefaults persistence.
import Foundation

/// Everything the user sets, and nothing transient: `playing` and `outputFailed`
/// are deliberately absent so the app can never launch producing sound.
struct SettingsSnapshot: Codable, Equatable {
    /// Bump when the shape changes incompatibly; unknown versions are discarded.
    static let currentVersion = 1

    /// Valid ranges, matching the UI sliders.
    static let frequencyRange: ClosedRange<Double> = 20 ... 20000
    static let amplitudeRange: ClosedRange<Double> = -60 ... 0
    static let phaseRange: ClosedRange<Double> = 0 ... 1
    static let masterGainRange: ClosedRange<Double> = -40 ... 0

    struct Channel: Codable, Equatable {
        var frequencyHz: Double
        var amplitudeDbfs: Double
        var phaseFraction: Double
        /// `Waveform.rawValue`; a String so an unknown case degrades to the default.
        var waveform: String
        var muted: Bool
    }

    var version: Int = SettingsSnapshot.currentVersion
    var left: Channel
    var right: Channel
    var masterGainDbfs: Double
    var linked: Bool

    /// Returns a copy with every number clamped into range (non-finite values
    /// replaced by the default) and unknown waveforms replaced by sine.
    func sanitized() -> SettingsSnapshot {
        var copy = self
        copy.left = left.sanitized()
        copy.right = right.sanitized()
        copy.masterGainDbfs = Self.clean(masterGainDbfs, Self.masterGainRange, fallback: 0)
        return copy
    }

    fileprivate static func clean(
        _ value: Double,
        _ range: ClosedRange<Double>,
        fallback: Double
    ) -> Double {
        guard value.isFinite else { return fallback }
        return min(max(value, range.lowerBound), range.upperBound)
    }

    // MARK: - Coding

    /// Encoding NaN/inf as strings keeps a save from failing outright and lets
    /// `sanitized()` reject them on load.
    static func encode(_ snapshot: SettingsSnapshot) -> Data? {
        let encoder = JSONEncoder()
        encoder.nonConformingFloatEncodingStrategy = .convertToString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan"
        )
        return try? encoder.encode(snapshot)
    }

    /// Decodes and sanitizes; nil for corrupt data or a version this build does not know.
    static func decode(_ data: Data) -> SettingsSnapshot? {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(
            positiveInfinity: "inf", negativeInfinity: "-inf", nan: "nan"
        )
        guard let snapshot = try? decoder.decode(SettingsSnapshot.self, from: data),
              snapshot.version == currentVersion
        else { return nil }
        return snapshot.sanitized()
    }
}

private extension SettingsSnapshot.Channel {
    func sanitized() -> SettingsSnapshot.Channel {
        typealias Limits = SettingsSnapshot
        return SettingsSnapshot.Channel(
            frequencyHz: Limits.clean(frequencyHz, Limits.frequencyRange, fallback: 440),
            amplitudeDbfs: Limits.clean(amplitudeDbfs, Limits.amplitudeRange, fallback: -12),
            phaseFraction: Limits.clean(phaseFraction, Limits.phaseRange, fallback: 0),
            waveform: Waveform(rawValue: waveform)?.rawValue ?? Waveform.sine.rawValue,
            muted: muted
        )
    }
}
