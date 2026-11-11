import XCTest
@testable import Tonegen

final class FrequencyMathTests: XCTestCase {
    // MARK: - Slider round-trip

    func testSliderRoundTrip() {
        let frequencies: [Double] = [20, 100, 440, 1000, 5000, 20000]
        for hz in frequencies {
            let result = sliderPositionToFreq(freqToSliderPosition(hz))
            XCTAssertEqual(result, hz, accuracy: hz * 1e-9, "Round-trip failed for \(hz) Hz")
        }
    }

    func testSliderBoundaries() {
        XCTAssertEqual(freqToSliderPosition(20), 0, accuracy: 1e-12)
        XCTAssertEqual(freqToSliderPosition(20000), 1, accuracy: 1e-12)
        XCTAssertEqual(sliderPositionToFreq(0), 20, accuracy: 1e-9)
        XCTAssertEqual(sliderPositionToFreq(1), 20000, accuracy: 1e-9)
    }

    // MARK: - freqToNote

    func testA4() {
        let (name, octave, cents) = freqToNote(440)
        XCTAssertEqual(name, "A")
        XCTAssertEqual(octave, 4)
        XCTAssertEqual(cents, 0)
    }

    func testA5() {
        let (name, octave, cents) = freqToNote(880)
        XCTAssertEqual(name, "A")
        XCTAssertEqual(octave, 5)
        XCTAssertEqual(cents, 0)
    }

    func testMiddleC() {
        // C4 ≈ 261.63 Hz
        let (name, octave, _) = freqToNote(261.626)
        XCTAssertEqual(name, "C")
        XCTAssertEqual(octave, 4)
    }

    func testCentsDeviation() {
        // 450 Hz is ~39 cents sharp of A4
        let (name, _, cents) = freqToNote(450)
        XCTAssertEqual(name, "A")
        XCTAssertTrue(cents > 0, "450 Hz should be sharp of A4")
    }
}
