import XCTest
@MainActor
final class QAFlowTests: XCTestCase {
    func launch(_ args: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = args
        app.launch()
        return app
    }
    func shot(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name; attachment.lifetime = .keepAlways
        add(attachment)
    }
    func study(_ args: [String]) {
        let app = launch(args)
        app.buttons["Study note"].tap()
        XCTAssertTrue(app.buttons["Flashcards"].waitForExistence(timeout: 10))
        shot("note")
        app.buttons["Flashcards"].tap()
        XCTAssertTrue(app.staticTexts["Card 1 of 2"].waitForExistence(timeout: 5))
        app.buttons["Answer"].tap()
        XCTAssertTrue(app.buttons["Question"].exists)
        app.buttons["Next card"].tap()
        XCTAssertTrue(app.staticTexts["Card 2 of 2"].exists)
        XCTAssertFalse(app.buttons["Next card"].isEnabled)
        shot("flashcards")
        app.buttons["Quiz"].tap()
        XCTAssertFalse(app.buttons["Check Answer"].isEnabled)
        app.buttons["Electron"].tap()
        app.buttons["Check Answer"].tap()
        XCTAssertFalse(app.buttons["Proton"].isEnabled)
        app.buttons["See Results"].tap()
        XCTAssertTrue(app.staticTexts["You scored 1 out of 1"].exists)
        app.buttons["Restart Quiz"].tap()
        XCTAssertFalse(app.buttons["Check Answer"].isEnabled)
        shot("quiz")
        app.buttons["Transcript"].tap()
        XCTAssertTrue(app.staticTexts["Electrons have a negative charge."].waitForExistence(timeout: 5))
        app.scrollViews.containing(.button, identifier: "Transcript").element(boundBy: 0).swipeLeft()
        app.buttons["Ask AI"].tap()
        XCTAssertTrue(app.textFields["Ask a question..."].waitForExistence(timeout: 5))
        app.textFields["Ask a question..."].tap()
        app.textFields["Ask a question..."].typeText("What is negative?")
        app.buttons["Send message"].tap()
        XCTAssertTrue(app.staticTexts["What is negative?"].waitForExistence(timeout: 5))
        shot("chat")
    }
    func testStudyLight() { study([]) }
    func testStudyDark() { study(["--dark"]) }
    func testErrorState() {
        let app = launch(["--error"])
        app.buttons["Study note"].tap()
        XCTAssertTrue(app.buttons["Retry"].waitForExistence(timeout: 5))
        shot("error")
    }
    func testProcessingState() {
        let app = launch(["--processing"])
        app.buttons["Study note"].tap()
        XCTAssertTrue(app.staticTexts["Transcribing fixture"].waitForExistence(timeout: 10))
        shot("processing")
    }
    func testRecordingCancel() {
        let app = launch()
        app.buttons["New recording"].tap()
        XCTAssertTrue(app.buttons["Start Recording"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Import Audio File"].exists)
        shot("recording")
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.navigationBars["Disposable QA"].waitForExistence(timeout: 5))
    }
    func testClassesCreate() {
        let app = launch()
        app.buttons["Classes"].tap()
        XCTAssertTrue(app.staticTexts["Physics"].waitForExistence(timeout: 5))
        app.buttons["Add Class"].tap()
        let name = app.alerts.textFields.element(boundBy: 0)
        name.tap(); name.typeText("Chemistry")
        app.alerts.buttons["Create"].tap()
        XCTAssertTrue(app.staticTexts["Chemistry"].waitForExistence(timeout: 5))
        shot("classes")
    }
    func testWelcomeLargeText() {
        let app = launch(["--large-text"])
        app.buttons["Welcome"].tap()
        let signIn = app.buttons["Sign in to Notes"]
        if !signIn.isHittable { app.swipeUp() }
        XCTAssertTrue(signIn.isHittable)
        shot("welcome-large-text")
    }
    func testWelcomeDark() {
        let app = launch(["--dark"])
        app.buttons["Welcome"].tap()
        XCTAssertTrue(app.buttons["Sign in to Notes"].exists)
        shot("welcome-dark")
    }
    func testRecordingDiscard() {
        let app = launch()
        app.buttons["New recording"].tap()
        app.buttons["Start Recording"].tap()
        let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["Allow"]
        if permission.waitForExistence(timeout: 2) { permission.tap() }
        XCTAssertTrue(app.buttons["Stop Recording"].waitForExistence(timeout: 5))
        app.buttons["Stop Recording"].tap()
        XCTAssertTrue(app.buttons["Process Note"].exists)
        XCTAssertTrue(app.buttons["Play audio preview"].exists)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Discard"].waitForExistence(timeout: 5))
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Process Note"].exists)
        shot("audio-preserved")
        app.buttons["Cancel"].tap()
        app.buttons["Discard"].tap()
        XCTAssertTrue(app.navigationBars["Disposable QA"].waitForExistence(timeout: 5))
    }
    func testEmptyStudy() {
        let app = launch()
        app.buttons["Empty flashcards"].tap()
        XCTAssertTrue(app.staticTexts["No Flashcards"].exists)
        shot("empty-cards")
        app.navigationBars.buttons.element(boundBy: 0).tap()
        app.buttons["Empty quiz"].tap()
        XCTAssertTrue(app.staticTexts["No Quiz Questions"].exists)
        shot("empty-quiz")
    }
}
