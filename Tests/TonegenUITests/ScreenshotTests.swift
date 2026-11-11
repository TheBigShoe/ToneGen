// Captures App Store screenshots by driving the real app through a few states.
// Run with the TonegenScreenshots scheme, then export the attachments:
//   xcrun xcresulttool export attachments --path <result>.xcresult --output-path <dir>
import XCTest

final class ScreenshotTests: XCTestCase {
    @MainActor
    func testCaptureStoreScreenshots() {
        let app = XCUIApplication()
        // Shadow the saved settings so screenshots always start from defaults,
        // whatever an earlier run left behind.
        app.launchArguments = ["-tonegen.settings.v1", "reset"]
        app.launch()

        // The link button only exists in the wide two-column layout.
        let wide = app.buttons["Unlink channels"].waitForExistence(timeout: 2)

        app.buttons["Play"].tap()
        snap("01-linked-sine")

        if wide {
            app.buttons["Unlink channels"].tap()
            app.buttons.matching(identifier: "Square wave").element(boundBy: 1).tap()
            app.buttons.matching(identifier: "1k").element(boundBy: 1).tap()
            snap("02-split-channels")

            app.buttons["Link channels"].tap()
            app.buttons.matching(identifier: "Pink noise").element(boundBy: 0).tap()
            snap("03-pink-noise")
        } else {
            app.buttons["Channel R"].tap()
            app.buttons["Square wave"].tap()
            app.buttons["1k"].tap()
            snap("02-right-channel")

            app.buttons["Link both channels"].tap()
            app.buttons["Pink noise"].tap()
            snap("03-pink-noise")
        }

        app.buttons["Pause"].tap()
    }

    @MainActor
    private func snap(_ name: String) {
        // Let button animations finish and the meters fill.
        Thread.sleep(forTimeInterval: 0.8)
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
