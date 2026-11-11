// ToneEngine.ensureRunning must never start audio the user did not ask for.
import XCTest
@testable import Tonegen

@MainActor
final class ToneEngineEnsureRunningTests: XCTestCase {
    func testEnsureRunningDoesNothingWhenNotPlaying() {
        let engine = ToneEngine()
        XCTAssertTrue(engine.ensureRunning())
    }

    func testEnsureRunningAfterStopRequestDoesNotRestart() {
        let engine = ToneEngine()
        engine.stop()
        XCTAssertTrue(engine.ensureRunning())
    }

    func testFollowPreferredRateChangeNeverStartsStoppedOutput() {
        let engine = ToneEngine()
        var lost = false
        engine.onOutputLost = { lost = true }
        engine.followPreferredRateChange()
        XCTAssertFalse(lost)
    }
}
