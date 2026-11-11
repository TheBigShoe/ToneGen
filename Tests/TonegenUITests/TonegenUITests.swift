// Interaction tests for the main iPhone flows. Audio output is never asserted.
import XCTest

final class TonegenUITests: XCTestCase {
    private var app = XCUIApplication()

    override func setUp() {
        continueAfterFailure = false
        app = XCUIApplication()
        // The persisted settings key is shadowed by a non-Data value in the argument
        // domain. The store reads that, finds no snapshot, and starts from defaults.
        // Relaunching without the argument sees what was actually saved.
        app.launchArguments = ["-tonegen.settings.v1", "reset"]
        app.launch()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 10))
    }

    // MARK: - Helpers

    private var readout: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "frequencyReadout").firstMatch
    }

    private var frequencyValue: String {
        _ = readout.waitForExistence(timeout: 5)
        return readout.value as? String ?? ""
    }

    private func expectFrequency(
        _ prefix: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let predicate = NSPredicate(format: "value BEGINSWITH %@", prefix)
        let exp = XCTNSPredicateExpectation(predicate: predicate, object: readout)
        let result = XCTWaiter().wait(for: [exp], timeout: 5)
        XCTAssertEqual(
            result, .completed,
            "Expected frequency starting \(prefix), got \(frequencyValue)",
            file: file, line: line
        )
    }

    // MARK: - Tests

    func testLaunchStartsStoppedWithDefaults() {
        XCTAssertTrue(app.buttons["Play"].exists)
        XCTAssertFalse(app.buttons["Pause"].exists)
        expectFrequency("440.00 Hz")
        XCTAssertTrue(app.buttons["Sine wave"].isSelected)
        XCTAssertTrue(app.buttons["Link both channels"].isSelected)
        XCTAssertTrue(app.buttons["Mute channel"].exists)
    }

    func testTransportTogglesPlayAndPause() {
        app.buttons["Play"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Play"].exists)

        app.buttons["Pause"].tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Pause"].exists)
    }

    func testWaveformChipsMarkSelection() {
        let labels = [
            "Square wave", "Triangle wave", "Sawtooth wave",
            "White noise", "Pink noise", "Sine wave"
        ]
        for label in labels {
            let chip = app.buttons[label]
            chip.tap()
            XCTAssertTrue(chip.isSelected, "\(label) should be selected after tap")
            for other in labels where other != label {
                XCTAssertFalse(app.buttons[other].isSelected, "\(other) selected with \(label)")
            }
        }
    }

    func testFrequencyPresets() {
        app.buttons["100"].tap()
        expectFrequency("100.00 Hz")
        app.buttons["1k"].tap()
        expectFrequency("1.000 kHz")
        app.buttons["10k"].tap()
        expectFrequency("10.00 kHz")
    }

    func testNudgeButtons() {
        app.buttons["1k"].tap()
        expectFrequency("1.000 kHz")

        app.buttons["Up one octave"].tap()
        expectFrequency("2.000 kHz")

        app.buttons["Down one octave"].tap()
        expectFrequency("1.000 kHz")

        app.buttons["Up one semitone"].tap()
        expectFrequency("1.059 kHz")

        app.buttons["Down one semitone"].tap()
        expectFrequency("1.000 kHz")
    }

    func testUnlinkedChannelsEditIndependentlyAndRelinkMirrors() {
        // Unlink by choosing CH·R; set R to 1k while L stays at 440.
        app.buttons["Channel R"].tap()
        XCTAssertTrue(app.buttons["Channel R"].isSelected)
        app.buttons["1k"].tap()
        expectFrequency("1.000 kHz")

        app.buttons["Channel L"].tap()
        XCTAssertTrue(app.buttons["Channel L"].isSelected)
        expectFrequency("440.00 Hz")

        app.buttons["Channel R"].tap()
        expectFrequency("1.000 kHz")

        // Relink: edits now apply to both channels.
        app.buttons["Link both channels"].tap()
        app.buttons["100"].tap()
        expectFrequency("100.00 Hz")

        app.buttons["Channel L"].tap()
        expectFrequency("100.00 Hz")
        app.buttons["Channel R"].tap()
        expectFrequency("100.00 Hz")
    }

    func testMuteTogglesLabel() {
        app.buttons["Mute channel"].tap()
        XCTAssertTrue(app.buttons["Unmute channel"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Mute channel"].exists)

        app.buttons["Unmute channel"].tap()
        XCTAssertTrue(app.buttons["Mute channel"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Unmute channel"].exists)
    }

    func testSettingsPersistAcrossRelaunchAndAppComesBackStopped() {
        app.buttons["Square wave"].tap()
        app.buttons["10k"].tap()
        expectFrequency("10.00 kHz")
        app.buttons["Play"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))

        // Backgrounding flushes the debounced save before the process is killed.
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10)
            || app.state == .runningBackgroundSuspended)
        app.terminate()

        // Relaunch without the reset argument so the real saved snapshot is read.
        app.launchArguments = []
        app.launch()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.buttons["Pause"].exists)
        expectFrequency("10.00 kHz")
        XCTAssertTrue(app.buttons["Square wave"].isSelected)
    }
}
