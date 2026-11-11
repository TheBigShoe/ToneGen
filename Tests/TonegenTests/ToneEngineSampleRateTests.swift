// The engine generates at the hardware rate and keeps its shared objects across rebuilds.
import XCTest
@testable import Tonegen

@MainActor
final class ToneEngineSampleRateTests: XCTestCase {
    func testOutputNodeRateWins() {
        let rate = ToneEngine.resolveSampleRate(outputNodeRate: 44100, sessionRate: 48000)
        XCTAssertEqual(rate, 44100)
    }

    func testFallsBackToSessionRateWhenOutputReportsNothing() {
        XCTAssertEqual(ToneEngine.resolveSampleRate(outputNodeRate: 0, sessionRate: 96000), 96000)
        XCTAssertEqual(
            ToneEngine.resolveSampleRate(outputNodeRate: .nan, sessionRate: 44100),
            44100
        )
    }

    func testFallsBackTo48kWhenNeitherIsUsable() {
        XCTAssertEqual(ToneEngine.resolveSampleRate(outputNodeRate: 0, sessionRate: 0), 48000)
        XCTAssertEqual(
            ToneEngine.resolveSampleRate(outputNodeRate: -1, sessionRate: .infinity),
            48000
        )
    }

    func testEngineStartsAtAUsableRate() {
        let engine = ToneEngine()
        XCTAssertTrue(engine.sampleRate.isFinite)
        XCTAssertGreaterThan(engine.sampleRate, 0)
    }

    /// The meters capture the scope buffers at launch and the store holds the bridge;
    /// a rebuild must keep feeding those same instances.
    func testRebuildKeepsSharedInstances() {
        let engine = ToneEngine()
        let scopeL = engine.scopeL
        let scopeR = engine.scopeR
        let bridge = engine.bridge
        engine.rebuild()
        XCTAssertTrue(engine.scopeL === scopeL)
        XCTAssertTrue(engine.scopeR === scopeR)
        XCTAssertTrue(engine.bridge === bridge)
    }
}
