// Interaction tests for the main iPhone flows. Audio output is never asserted.
import XCTest

@MainActor
final class TonegenUITests: XCTestCase {
    /// Implicitly unwrapped because XCUIApplication is main-actor isolated and cannot be
    /// a default value of a property that XCTestCase's nonisolated init sets up.
    private var app: XCUIApplication!

    /// Async so the override runs on the main actor like the rest of the class.
    override func setUp() async throws {
        try await super.setUp()
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

    // MARK: - Runtime isolation

    // These keep audio running so a trap on the render thread, in the meter loop or in a
    // lifecycle callback kills the app and fails the test instead of passing unnoticed.

    func testSustainedPlaybackThroughEveryWaveform() {
        app.buttons["Play"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))

        let labels = [
            "Sine wave", "Square wave", "Triangle wave",
            "Sawtooth wave", "White noise", "Pink noise"
        ]
        for label in labels {
            app.buttons[label].firstMatch.tap()
        }
        app.buttons["1k"].firstMatch.tap()

        // The one timed wait: audio has to keep rendering (and the meters keep reading)
        // for long enough that a trap on either thread would have killed the app.
        let elapsed = expectation(description: "sustained playback")
        elapsed.isInverted = true
        wait(for: [elapsed], timeout: 3)

        XCTAssertEqual(app.state, .runningForeground)
        XCTAssertTrue(app.buttons["Pause"].exists)
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
    }

    func testPlaybackSurvivesBackgroundAndReturn() {
        app.buttons["Play"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))

        // Resign-active and did-enter-background fire the store's lifecycle observers.
        XCUIDevice.shared.press(.home)
        XCTAssertTrue(app.wait(for: .runningBackground, timeout: 10))
        app.activate()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))

        // Background audio is enabled, so the tone is still playing on return.
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: - Sample rate menu

    private var rateMenu: XCUIElement {
        app.descendants(matching: .any).matching(identifier: "sampleRateMenu").firstMatch
    }

    private func chooseRate(_ title: String) {
        XCTAssertTrue(rateMenu.waitForExistence(timeout: 5))
        rateMenu.tap()
        let item = app.buttons[title]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "Menu item \(title) missing")
        item.tap()
    }

    func testPickingARateKeepsAppRunningAndReportsIt() {
        chooseRate("44.1 kHz")
        XCTAssertEqual(app.state, .runningForeground)
        // The simulator may or may not honour the request; either way the value must
        // state the rate as actual or as requested.
        let value = rateMenu.value as? String ?? ""
        XCTAssertTrue(value.contains("44.1"), "Menu value was \(value)")
    }

    func testPickingARateWhilePlayingKeepsPlaying() {
        app.buttons["Play"].tap()
        XCTAssertTrue(app.buttons["Pause"].waitForExistence(timeout: 5))
        chooseRate("96 kHz")
        XCTAssertEqual(app.state, .runningForeground)
        // Give a restart at a new rate time to fail, if it is going to.
        sleep(1)
        XCTAssertTrue(app.buttons["Pause"].exists)
        let value = rateMenu.value as? String ?? ""
        XCTAssertTrue(value.contains("96") || value.contains("kHz"), "Menu value was \(value)")
        app.buttons["Pause"].tap()
        XCTAssertTrue(app.buttons["Play"].waitForExistence(timeout: 5))
    }
}
