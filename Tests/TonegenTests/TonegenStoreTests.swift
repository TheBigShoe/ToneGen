// Verifies TonegenStore mutators keep EngineParams in sync and that LINK mode works.
import XCTest
@testable import Tonegen

@MainActor
final class TonegenStoreTests: XCTestCase {
    // MARK: - Bridge sync

    func testSetPlayingUpdatesBridge() throws {
        let (store, bridge) = makeStore()
        store.setPlaying(true)
        XCTAssertTrue(try XCTUnwrap(bridge.snapshot()?.playing))
        store.setPlaying(false)
        XCTAssertFalse(try XCTUnwrap(bridge.snapshot()?.playing))
    }

    func testSetWaveformUpdatesBridge() {
        let (store, bridge) = makeStore()
        store.setWaveform(.saw, for: .left)
        XCTAssertEqual(bridge.snapshot()?.left.waveform, .saw)
    }

    func testSetFrequencyUpdatesBridge() throws {
        let (store, bridge) = makeStore()
        store.setFrequency(880, for: .left)
        XCTAssertEqual(try XCTUnwrap(bridge.snapshot()?.left.frequencyHz), 880, accuracy: 0.01)
    }

    func testSetAmplitudeUpdatesBridge() throws {
        let (store, bridge) = makeStore()
        store.setAmplitude(-6, for: .right)
        XCTAssertEqual(try XCTUnwrap(bridge.snapshot()?.right.amplitudeDbfs), -6, accuracy: 0.01)
    }

    func testSetPhaseUpdatesBridge() throws {
        let (store, bridge) = makeStore()
        store.setPhase(0.5, for: .left)
        XCTAssertEqual(try XCTUnwrap(bridge.snapshot()?.left.phaseFraction), 0.5, accuracy: 0.001)
    }

    func testSetMasterGainUpdatesBridge() throws {
        let (store, bridge) = makeStore()
        store.setMasterGain(-3)
        XCTAssertEqual(try XCTUnwrap(bridge.snapshot()?.masterGainDbfs), -3, accuracy: 0.01)
    }

    // MARK: - LINK mode

    func testLinkedWaveformUpdatesRightToo() throws {
        let (store, bridge) = makeStore()
        store.linked = true
        store.setWaveform(.square, for: .left)
        let p = try XCTUnwrap(bridge.snapshot())
        XCTAssertEqual(p.left.waveform, .square)
        XCTAssertEqual(p.right.waveform, .square)
    }

    func testLinkedFrequencyUpdatesBothChannels() throws {
        let (store, bridge) = makeStore()
        store.linked = true
        store.setFrequency(1000, for: .right)
        let p = try XCTUnwrap(bridge.snapshot())
        XCTAssertEqual(p.left.frequencyHz, 1000, accuracy: 0.01)
        XCTAssertEqual(p.right.frequencyHz, 1000, accuracy: 0.01)
    }

    func testUnlinkedFrequencyUpdatesOneChannel() throws {
        let (store, bridge) = makeStore()
        store.linked = false
        store.setFrequency(880, for: .left)
        let p = try XCTUnwrap(bridge.snapshot())
        XCTAssertEqual(p.left.frequencyHz, 880, accuracy: 0.01)
        XCTAssertEqual(p.right.frequencyHz, 440, accuracy: 0.01) // default, unchanged
    }

    // MARK: - onFirstPlay callback

    func testOnFirstPlayFiredOnceOnly() {
        var callCount = 0
        let bridge = ParamsBridge()
        let store = TonegenStore(bridge: bridge) { callCount += 1 }
        store.setPlaying(true)
        store.setPlaying(false)
        store.setPlaying(true)
        XCTAssertEqual(
            callCount,
            2,
            "Callback fires every time playing transitions from false→true"
        )
    }

    // MARK: - Helpers

    private func makeStore() -> (TonegenStore, ParamsBridge) {
        let bridge = ParamsBridge()
        let store = TonegenStore(bridge: bridge)
        return (store, bridge)
    }
}
