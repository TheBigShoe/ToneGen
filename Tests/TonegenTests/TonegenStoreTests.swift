// Verifies TonegenStore mutators keep EngineParams in sync and that LINK mode works.
import XCTest
@testable import Tonegen

@MainActor
final class TonegenStoreTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard

    // Async so the overrides run on the main actor like the rest of the class.
    override func setUp() async throws {
        try await super.setUp()
        suiteName = "TonegenStoreTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

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

    // MARK: - Output lifecycle

    func testOutputStartsAndStopsWithTransport() {
        var starts = 0
        var stops = 0
        let store = TonegenStore(
            bridge: ParamsBridge(),
            startOutput: { starts += 1; return true },
            stopOutput: { stops += 1 },
            defaults: defaults
        )
        store.setPlaying(true)
        store.setPlaying(true) // already playing — must not start twice
        store.setPlaying(false)
        store.setPlaying(true)
        XCTAssertEqual(starts, 2)
        XCTAssertEqual(stops, 1)
    }

    func testFailedStartLeavesStoreStopped() throws {
        let bridge = ParamsBridge()
        let store = TonegenStore(bridge: bridge, startOutput: { false }, defaults: defaults)
        store.setPlaying(true)
        XCTAssertFalse(store.playing)
        XCTAssertTrue(store.outputFailed)
        XCTAssertFalse(try XCTUnwrap(bridge.snapshot()?.playing))
    }

    func testSuccessfulStartClearsFailure() {
        // A box rather than a captured `var`: the output closures are Sendable, and a
        // Sendable closure may not capture a variable that is mutated afterwards.
        final class Outcome { var succeed = false }
        let outcome = Outcome()
        let store = TonegenStore(
            bridge: ParamsBridge(), startOutput: { outcome.succeed }, defaults: defaults
        )
        store.setPlaying(true)
        outcome.succeed = true
        store.setPlaying(true)
        XCTAssertTrue(store.playing)
        XCTAssertFalse(store.outputFailed)
    }

    func testOutputLostStopsAndFlagsFailure() throws {
        let (store, bridge) = makeStore()
        store.setPlaying(true)
        store.outputLost()
        XCTAssertFalse(store.playing)
        XCTAssertTrue(store.outputFailed)
        XCTAssertFalse(try XCTUnwrap(bridge.snapshot()?.playing))
    }

    // MARK: - Interruptions

    func testInterruptionPausesAndResumesWhenAllowed() {
        let (store, _) = makeStore()
        store.setPlaying(true)
        store.interruptionBegan()
        XCTAssertFalse(store.playing)
        store.interruptionEnded(shouldResume: true)
        XCTAssertTrue(store.playing)
    }

    func testInterruptionWithoutResumeStaysStopped() {
        let (store, _) = makeStore()
        store.setPlaying(true)
        store.interruptionBegan()
        store.interruptionEnded(shouldResume: false)
        XCTAssertFalse(store.playing)
    }

    func testInterruptionWhileStoppedDoesNotStartPlayback() {
        let (store, _) = makeStore()
        store.interruptionBegan()
        store.interruptionEnded(shouldResume: true)
        XCTAssertFalse(store.playing)
    }

    func testUserStopDuringInterruptionCancelsResume() {
        let (store, _) = makeStore()
        store.setPlaying(true)
        store.interruptionBegan()
        store.setPlaying(false)
        store.interruptionEnded(shouldResume: true)
        XCTAssertFalse(store.playing)
    }

    // MARK: - Helpers

    private func makeStore() -> (TonegenStore, ParamsBridge) {
        let bridge = ParamsBridge()
        let store = TonegenStore(bridge: bridge, defaults: defaults)
        return (store, bridge)
    }
}
