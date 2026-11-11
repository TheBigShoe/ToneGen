// Verifies the requested output rate: default, validation, persistence, apply hook, labels.
import XCTest
@testable import Tonegen

@MainActor
final class RequestedSampleRateTests: XCTestCase {
    private var suiteName = ""
    private var defaults = UserDefaults.standard

    /// Async so the overrides run on the main actor like the rest of the class.
    override func setUp() async throws {
        try await super.setUp()
        suiteName = "RequestedSampleRateTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName) ?? .standard
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
        try await super.tearDown()
    }

    /// Collects the rates passed to the apply hook.
    private final class Applied {
        var rates: [Double] = []
    }

    private func makeStore(_ applied: Applied = Applied()) -> TonegenStore {
        TonegenStore(
            bridge: ParamsBridge(),
            applySampleRate: { applied.rates.append($0) },
            defaults: defaults
        )
    }

    private func write(_ json: String) {
        defaults.set(Data(json.utf8), forKey: TonegenStore.settingsKey)
    }

    private func blob(rateField: String) -> String {
        let ch = """
        {"frequencyHz":1000,"amplitudeDbfs":-6,"phaseFraction":0.25,\
        "waveform":"square","muted":false}
        """
        return """
        {"version":1,"left":\(ch),"right":\(ch),"masterGainDbfs":-3,"linked":true\(rateField)}
        """
    }

    func testDefaultIs48k() {
        XCTAssertEqual(makeStore().requestedSampleRate, 48000)
        XCTAssertEqual(TonegenStore.allowedSampleRates.count, 6)
    }

    func testSetterRejectsRatesOutsideTheList() {
        let applied = Applied()
        let s = makeStore(applied)
        s.setRequestedSampleRate(22050)
        s.setRequestedSampleRate(.nan)
        XCTAssertEqual(s.requestedSampleRate, 48000)
        XCTAssertTrue(applied.rates.isEmpty)
    }

    func testHookFiresOncePerActualChange() {
        let applied = Applied()
        let s = makeStore(applied)
        s.setRequestedSampleRate(48000)
        XCTAssertTrue(applied.rates.isEmpty)
        s.setRequestedSampleRate(96000)
        s.setRequestedSampleRate(96000)
        XCTAssertEqual(applied.rates, [96000])
        s.setRequestedSampleRate(44100)
        XCTAssertEqual(applied.rates, [96000, 44100])
    }

    func testPersistenceRoundTripDoesNotFireHook() {
        let first = makeStore()
        first.setRequestedSampleRate(192_000)
        first.flushSettings()
        let applied = Applied()
        let second = makeStore(applied)
        XCTAssertEqual(second.requestedSampleRate, 192_000)
        XCTAssertTrue(applied.rates.isEmpty)
        XCTAssertEqual(TonegenStore.savedSampleRate(defaults: defaults), 192_000)
    }

    func testOldBlobWithoutFieldYields48k() {
        write(blob(rateField: ""))
        XCTAssertEqual(makeStore().requestedSampleRate, 48000)
        XCTAssertEqual(TonegenStore.savedSampleRate(defaults: defaults), 48000)
    }

    func testOutOfListSavedValueYields48k() {
        write(blob(rateField: ",\"requestedSampleRate\":12345"))
        XCTAssertEqual(makeStore().requestedSampleRate, 48000)
        XCTAssertEqual(TonegenStore.savedSampleRate(defaults: defaults), 48000)
    }

    func testValidSavedValueIsKept() {
        write(blob(rateField: ",\"requestedSampleRate\":88200"))
        XCTAssertEqual(makeStore().requestedSampleRate, 88200)
    }

    func testLabelsWhenRatesMatch() {
        XCTAssertEqual(OutputRate.menuLabel(actual: 44100, requested: 44100), "44.1 kHz · iOS")
        XCTAssertEqual(
            OutputRate.accessibilityValue(actual: 48000, requested: 48000), "48 kHz"
        )
    }

    func testLabelsWhenRatesDiffer() {
        XCTAssertEqual(OutputRate.menuLabel(actual: 48000, requested: 96000), "48 kHz · 96 req")
        XCTAssertEqual(
            OutputRate.menuLabel(actual: 44100, requested: 176_400), "44.1 kHz · 176.4 req"
        )
        XCTAssertEqual(
            OutputRate.accessibilityValue(actual: 48000, requested: 96000),
            "48 kHz, 96 kHz requested"
        )
    }
}
