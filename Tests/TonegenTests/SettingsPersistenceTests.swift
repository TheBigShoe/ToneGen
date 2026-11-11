// Verifies settings persistence: round trip, sanitising, versioning and debouncing.
import XCTest
@testable import Tonegen

@MainActor
final class SettingsPersistenceTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard

    /// Async so the overrides run on the main actor like the rest of the class.
    override func setUp() async throws {
        try await super.setUp()
        suiteName = "SettingsPersistenceTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    private func makeStore(
        bridge: ParamsBridge = ParamsBridge(),
        delay: Duration = .milliseconds(500)
    ) -> TonegenStore {
        TonegenStore(bridge: bridge, defaults: defaults, saveDelay: delay)
    }

    private func write(_ json: String) {
        defaults.set(Data(json.utf8), forKey: TonegenStore.settingsKey)
    }

    private func snapshotJSON(
        version: Int = 1,
        freq: String = "1000",
        amp: String = "-6",
        phase: String = "0.25",
        wave: String = "square",
        master: String = "-3"
    ) -> String {
        let ch = """
        {"frequencyHz":\(freq),"amplitudeDbfs":\(amp),"phaseFraction":\(phase),\
        "waveform":"\(wave)","muted":true}
        """
        return """
        {"version":\(version),"left":\(ch),"right":\(ch),"masterGainDbfs":\(master),"linked":false}
        """
    }

    func testRoundTripRestoresValues() {
        let first = makeStore()
        first.linked = false
        first.setWaveform(.saw, for: .left)
        first.setFrequency(1234, for: .left)
        first.setAmplitude(-20, for: .right)
        first.setPhase(0.5, for: .right)
        first.setMuted(true, for: .right)
        first.setMasterGain(-10)
        first.flushSettings()

        let second = makeStore()
        XCTAssertFalse(second.linked)
        XCTAssertEqual(second.left.waveform, .saw)
        XCTAssertEqual(second.left.frequencyHz, 1234, accuracy: 0.001)
        XCTAssertEqual(second.right.frequencyHz, 440, accuracy: 0.001)
        XCTAssertEqual(second.right.amplitudeDbfs, -20, accuracy: 0.001)
        XCTAssertEqual(second.right.phaseFraction, 0.5, accuracy: 0.001)
        XCTAssertTrue(second.right.muted)
        XCTAssertEqual(second.masterGainDbfs, -10, accuracy: 0.001)
    }

    func testRestoredValuesReachBridgeOnInit() throws {
        let first = makeStore()
        first.setFrequency(2000, for: .both)
        first.flushSettings()
        let bridge = ParamsBridge()
        _ = makeStore(bridge: bridge)
        XCTAssertEqual(try XCTUnwrap(bridge.snapshot()?.left.frequencyHz), 2000, accuracy: 0.01)
    }

    func testPlayingIsNeverRestored() throws {
        let first = makeStore()
        first.setPlaying(true)
        first.setFrequency(500, for: .both)
        first.flushSettings()
        let bridge = ParamsBridge()
        let second = makeStore(bridge: bridge)
        XCTAssertFalse(second.playing)
        XCTAssertFalse(second.outputFailed)
        XCTAssertFalse(try XCTUnwrap(bridge.snapshot()?.playing))
        let stored = try XCTUnwrap(defaults.data(forKey: TonegenStore.settingsKey))
        let text = String(bytes: stored, encoding: .utf8) ?? ""
        XCTAssertFalse(text.contains("playing"))
        XCTAssertFalse(text.contains("outputFailed"))
    }

    func testCorruptDataFallsBackToDefaults() {
        defaults.set(Data("not json {".utf8), forKey: TonegenStore.settingsKey)
        let s = makeStore()
        XCTAssertEqual(s.left.frequencyHz, 440)
        XCTAssertEqual(s.left.amplitudeDbfs, -12)
        XCTAssertTrue(s.linked)
    }

    func testWrongTypeDataFallsBackToDefaults() {
        defaults.set("a string", forKey: TonegenStore.settingsKey)
        XCTAssertEqual(makeStore().left.frequencyHz, 440)
    }

    func testUnknownSchemaVersionFallsBackToDefaults() {
        write(snapshotJSON(version: 99))
        let s = makeStore()
        XCTAssertEqual(s.left.frequencyHz, 440)
        XCTAssertTrue(s.linked)
    }

    func testValidJSONIsRestored() {
        write(snapshotJSON())
        let s = makeStore()
        XCTAssertEqual(s.left.frequencyHz, 1000)
        XCTAssertEqual(s.left.waveform, .square)
        XCTAssertEqual(s.masterGainDbfs, -3)
    }

    func testOutOfRangeValuesAreClamped() {
        write(snapshotJSON(freq: "999999", amp: "12", phase: "7", master: "-500"))
        let s = makeStore()
        XCTAssertEqual(s.left.frequencyHz, 20000)
        XCTAssertEqual(s.left.amplitudeDbfs, 0)
        XCTAssertEqual(s.left.phaseFraction, 1)
        XCTAssertEqual(s.masterGainDbfs, -40)

        write(snapshotJSON(freq: "-5", amp: "-900", phase: "-1", master: "9"))
        let t = makeStore()
        XCTAssertEqual(t.left.frequencyHz, 20)
        XCTAssertEqual(t.left.amplitudeDbfs, -60)
        XCTAssertEqual(t.left.phaseFraction, 0)
        XCTAssertEqual(t.masterGainDbfs, 0)
    }

    func testNonFiniteValuesAreRejected() {
        write(snapshotJSON(freq: "\"nan\"", amp: "\"inf\"", phase: "\"-inf\"", master: "\"nan\""))
        let s = makeStore()
        XCTAssertEqual(s.left.frequencyHz, 440)
        XCTAssertEqual(s.left.amplitudeDbfs, -12)
        XCTAssertEqual(s.left.phaseFraction, 0)
        XCTAssertEqual(s.masterGainDbfs, 0)
    }

    func testNonFiniteStoreValuesStillSaveAsDefaults() {
        let first = makeStore()
        first.setFrequency(.nan, for: .both)
        first.flushSettings()
        XCTAssertEqual(makeStore().left.frequencyHz, 440)
    }

    func testUnknownWaveformFallsBackToSine() {
        write(snapshotJSON(wave: "wobble"))
        XCTAssertEqual(makeStore().left.waveform, .sine)
    }

    func testSaveIsDebouncedAndCoalesced() async throws {
        let s = makeStore(delay: .milliseconds(150))
        for hz in [100.0, 200, 300, 400] {
            s.setFrequency(hz, for: .both)
        }
        XCTAssertNil(defaults.data(forKey: TonegenStore.settingsKey), "must not write per change")
        try await Task.sleep(for: .milliseconds(600))
        let data = try XCTUnwrap(defaults.data(forKey: TonegenStore.settingsKey))
        XCTAssertEqual(SettingsSnapshot.decode(data)?.left.frequencyHz, 400)
        withExtendedLifetime(s) {}
    }

    func testFlushWritesImmediately() throws {
        let s = makeStore()
        s.setFrequency(777, for: .both)
        XCTAssertNil(defaults.data(forKey: TonegenStore.settingsKey))
        s.flushSettings()
        let data = try XCTUnwrap(defaults.data(forKey: TonegenStore.settingsKey))
        XCTAssertEqual(SettingsSnapshot.decode(data)?.left.frequencyHz, 777)
    }

    func testBackgroundNotificationFlushes() throws {
        let s = makeStore()
        s.setFrequency(555, for: .both)
        NotificationCenter.default.post(
            name: UIApplication.didEnterBackgroundNotification, object: nil
        )
        let data = try XCTUnwrap(defaults.data(forKey: TonegenStore.settingsKey))
        XCTAssertEqual(SettingsSnapshot.decode(data)?.left.frequencyHz, 555)
        withExtendedLifetime(s) {}
    }
}
