// All waveforms the generator can produce.
import Foundation

enum Waveform: String, CaseIterable, Identifiable {
    case sine
    case square
    case triangle
    case saw
    case whiteNoise
    case pinkNoise

    var id: String {
        rawValue
    }

    var label: String {
        switch self {
        case .sine: "SIN"
        case .square: "SQR"
        case .triangle: "TRI"
        case .saw: "SAW"
        case .whiteNoise: "WHT"
        case .pinkNoise: "PNK"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .sine: "Sine wave"
        case .square: "Square wave"
        case .triangle: "Triangle wave"
        case .saw: "Sawtooth wave"
        case .whiteNoise: "White noise"
        case .pinkNoise: "Pink noise"
        }
    }
}
