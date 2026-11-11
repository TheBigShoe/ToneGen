// Frequency ↔ slider position and frequency ↔ musical note conversions.
// All conversions are pure functions — no state, no allocation.
import Foundation

// MARK: - Slider ↔ Frequency (logarithmic scale, 20 Hz – 20 kHz)

private let freqMin: Double = 20
private let freqMax: Double = 20000
private let logFreqMin = log(freqMin)
private let logFreqMax = log(freqMax)

/// Maps a frequency in Hz to a normalized slider position in [0, 1].
func freqToSliderPosition(_ hz: Double) -> Double {
    (log(hz.clamped(to: freqMin ... freqMax)) - logFreqMin) / (logFreqMax - logFreqMin)
}

/// Maps a normalized slider position in [0, 1] to a frequency in Hz.
func sliderPositionToFreq(_ s: Double) -> Double {
    exp(logFreqMin + s.clamped(to: 0 ... 1) * (logFreqMax - logFreqMin))
}

// MARK: - Frequency → Musical Note

private let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

/// Returns the nearest note name, octave, and cent deviation for a given frequency.
/// Cents are in the range [−50, +50].
func freqToNote(_ hz: Double) -> (name: String, octave: Int, cents: Int) {
    // MIDI note 69 = A4 = 440 Hz
    let semitones = 12 * log2(hz / 440.0) + 69
    let rounded = semitones.rounded()
    let cents = Int(((semitones - rounded) * 100).rounded())
    let midi = Int(rounded)
    let noteIndex = ((midi % 12) + 12) % 12
    let octave = (midi / 12) - 1
    return (noteNames[noteIndex], octave, cents)
}

// MARK: - Private

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
