import XCTest
@testable import Notes

@MainActor
final class NoteSharingTests: XCTestCase {
    private func info(_ json: String) throws -> NoteShareInfo {
        try JSONDecoder().decode(NoteShareInfo.self, from: Data(json.utf8))
    }

    func testMainURLOnlyResponse() throws {
        XCTAssertNotNil(try info(#"{"shareUrl":"https://notes.kobosh.com/shared/test"}"#).activeURL)
        XCTAssertNil(try info(#"{"shareUrl":null}"#).activeURL)
    }

    func testDisabledExpiredAndUnsafeLinksAreNotOffered() throws {
        for json in [
            #"{"shareUrl":"https://notes.kobosh.com/shared/test","shareEnabled":false}"#,
            #"{"shareUrl":"https://notes.kobosh.com/shared/test","shareEnabled":true,"shareExpiresAt":"2020-01-01T00:00:00.000Z"}"#,
            #"{"shareUrl":"javascript:alert(1)"}"#,
            #"{"shareUrl":"http://notes.kobosh.com/shared/test"}"#,
            #"{"shareUrl":"https://user:pass@notes.kobosh.com/shared/test"}"#
        ] { XCTAssertNil(try info(json).activeURL) }
    }

    func testPR4ResponseAndDateFormats() throws {
        let result = try info(#"{"shareUrl":"https://notes.kobosh.com/shared/test","shareEnabled":true,"shareExpiresAt":"2099-01-01T00:00:00Z","shareAllowChat":false}"#)
        XCTAssertNotNil(result.activeURL)
        XCTAssertNotNil(result.expiration)
        XCTAssertEqual(result.shareAllowChat, false)
    }

    func testLoadEnableDisableAndRefresh() async throws {
        var enabled = false
        let inactive = try info(#"{"shareUrl":null}"#)
        let active = try info(#"{"shareUrl":"https://notes.kobosh.com/shared/test"}"#)
        let model = NoteSharingModel(fetch: { enabled ? active : inactive }, create: { enabled = true; return active }, remove: { enabled = false })
        await model.enable()
        XCTAssertFalse(enabled)
        await model.load()
        XCTAssertTrue(model.hasLoaded)
        await model.enable()
        XCTAssertTrue(enabled)
        XCTAssertNotNil(model.info?.activeURL)
        await model.disable()
        XCTAssertFalse(enabled)
        XCTAssertNil(model.info?.activeURL)
        await model.load()
        XCTAssertTrue(model.hasLoaded)
        XCTAssertNil(model.info?.activeURL)
    }

    func testFailedLoadDoesNotPermitCreate() async {
        var created = false
        let model = NoteSharingModel(fetch: { throw APIError.notSignedIn }, create: { created = true; throw APIError.notSignedIn }, remove: {})
        await model.load()
        await model.enable()
        XCTAssertFalse(created)
        XCTAssertFalse(model.hasLoaded)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertFalse(model.isWorking)
    }

    func testFailedDisableClearsStaleLinkAndRequiresRefresh() async throws {
        let active = try info(#"{"shareUrl":"https://notes.kobosh.com/shared/test"}"#)
        let model = NoteSharingModel(fetch: { active }, create: { active }, remove: { throw APIError.network("Lost response") })
        await model.load()
        await model.disable()
        XCTAssertNil(model.info)
        XCTAssertFalse(model.hasLoaded)
        XCTAssertNotNil(model.errorMessage)
        await model.load()
        XCTAssertNotNil(model.info?.activeURL)
        XCTAssertNil(model.errorMessage)
    }

    func testRepeatedCreateIsIgnoredWhileWorking() async throws {
        let inactive = try info(#"{"shareUrl":null}"#)
        let active = try info(#"{"shareUrl":"https://notes.kobosh.com/shared/test"}"#)
        var count = 0
        let model = NoteSharingModel(fetch: { inactive }, create: {
            count += 1
            try await Task.sleep(for: .milliseconds(20))
            return active
        }, remove: {})
        await model.load()
        let first = Task { await model.enable() }
        await Task.yield()
        await model.enable()
        await first.value
        XCTAssertEqual(count, 1)
    }

    func testMarkdownIncludesStudyMaterialAndSafeFilename() {
        let note = NoteItem(_id: "x", title: "../Chemistry/🧪", content: "Atoms", flashcards: [.init(front: "Q", back: "A")], quizQuestions: [.init(question: "Why?", wrongAnswers: [], correctAnswer: "Because", explanation: "Details")])
        let export = NoteMarkdownExport(note: note)
        XCTAssertEqual(export.filename, "Chemistry.md")
        for part in ["Atoms", "Flashcards", "**Q:** Q", "**A:** A", "Quiz", "Answer: Because", "Details"] {
            XCTAssertTrue(export.text.contains(part))
        }
        XCTAssertEqual(NoteMarkdownExport(note: NoteItem(_id: "y", title: "../")).filename, "Note.md")
    }
}
