import XCTest

final class SharingUITests: XCTestCase {
    @MainActor
    private func launch(_ args: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        return app
    }

    @MainActor
    private func shot(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testLightEnableCopyWithoutRevocationUI() {
        let app = launch()
        let enable = app.buttons["Enable Public Link"]
        XCTAssertTrue(enable.waitForExistence(timeout: 5))
        shot("sharing-light-private", app)
        enable.tap()
        let copy = app.buttons["Copy Link"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        copy.tap()
        XCTAssertTrue(app.staticTexts["Link copied."].exists)
        shot("sharing-light-public", app)
        XCTAssertFalse(app.buttons["Disable Public Link"].exists)
        XCTAssertFalse(app.buttons["Delete Share Link"].exists)

    }

    @MainActor
    func testDarkAndNativeLinkSheet() {
        let app = launch(["--dark"])
        XCTAssertTrue(app.buttons["Enable Public Link"].waitForExistence(timeout: 5))
        shot("sharing-dark-private", app)
        app.buttons["Enable Public Link"].tap()
        XCTAssertTrue(app.buttons["Share Link"].waitForExistence(timeout: 5))
        shot("sharing-dark-public", app)
        app.buttons["Share Link"].tap()
        XCTAssertTrue(app.cells["Copy"].waitForExistence(timeout: 5))
        shot("sharing-native-link-sheet", app)
    }

    @MainActor
    func testNativeTextSheet() {
        let app = launch()
        XCTAssertTrue(app.buttons["Share Note Text"].waitForExistence(timeout: 5))
        app.buttons["Share Note Text"].tap()
        XCTAssertTrue(app.cells["Copy"].waitForExistence(timeout: 5))
        shot("sharing-native-text-sheet", app)
    }

    @MainActor
    func testNativeMarkdownSheet() {
        let app = launch()
        XCTAssertTrue(app.buttons["Export Markdown"].waitForExistence(timeout: 5))
        app.buttons["Export Markdown"].tap()
        XCTAssertTrue(app.cells["Save to Files"].waitForExistence(timeout: 5))
        shot("sharing-native-markdown-sheet", app)
    }

    @MainActor
    func testFailureDoesNotEnableUnknownSharingState() {
        let app = launch(["--error"])
        XCTAssertTrue(app.buttons["Retry"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["Enable Public Link"].exists)
        XCTAssertTrue(app.buttons["Share Note Text"].exists)
        shot("sharing-load-error", app)
    }
}
