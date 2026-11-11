// The header must show the generator's rate exactly, including fractional kHz.
import XCTest
@testable import Tonegen

@MainActor
final class OutputRateTests: XCTestCase {
    func testLabelFormatsCommonRates() {
        XCTAssertEqual(OutputRate.label(for: 44100), "44.1 kHz · iOS")
        XCTAssertEqual(OutputRate.label(for: 48000), "48 kHz · iOS")
        XCTAssertEqual(OutputRate.label(for: 88200), "88.2 kHz · iOS")
        XCTAssertEqual(OutputRate.label(for: 96000), "96 kHz · iOS")
        XCTAssertEqual(OutputRate.label(for: 22050), "22.05 kHz · iOS")
        XCTAssertEqual(OutputRate.label(for: 192_000), "192 kHz · iOS")
    }

    func testUpdateRecordsEngineRate() {
        let rate = OutputRate(sampleRate: 48000)
        rate.update(44100)
        XCTAssertEqual(rate.sampleRate, 44100)
    }

    func testSeededFromEngine() {
        let engine = ToneEngine()
        let rate = OutputRate(sampleRate: engine.sampleRate)
        XCTAssertEqual(rate.sampleRate, engine.sampleRate)
    }
}
