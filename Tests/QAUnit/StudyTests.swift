import XCTest
final class StudyTests: XCTestCase {
    func testQuizDeduplicatesAndRemovesBlankChoices() {
        let question = QuizQuestion(question: "Charge?", wrongAnswers: ["Proton", "Proton", "Electron", "", "  "], correctAnswer: "Electron")
        for _ in 0..<100 {
            XCTAssertEqual(Set(question.allOptions), Set(["Proton", "Electron"]))
            XCTAssertEqual(question.allOptions.count, 2)
        }
    }
    func testLegacyQuizDecodesAndRoundTrips() throws {
        let question = try JSONDecoder().decode(QuizQuestion.self, from: Data(#"{"question":"Q","options":["A","B","B",""],"correctAnswer":"A"}"#.utf8))
        XCTAssertEqual(Set(question.allOptions), Set(["A", "B"]))
        XCTAssertEqual(try JSONDecoder().decode(QuizQuestion.self, from: JSONEncoder().encode(question)), question)
    }
    func testNoteSafeDecoding() throws {
        let note = try JSONDecoder().decode(NoteItem.self, from: Data(#"{"id":"fixture","originalFileName":"lecture.wav","status":"queued","duration":"65","flashcards":[{"question":"Q","answer":"A"},null],"quizQuestions":[false,{"question":"Q","correctAnswer":"A"}]}"#.utf8))
        XCTAssertEqual(note.id, "fixture")
        XCTAssertEqual(note.title, "lecture.wav")
        XCTAssertTrue(note.isProcessing)
        XCTAssertEqual(note.formattedDuration, "1:05")
        XCTAssertEqual(note.flashcards?.count, 1)
        XCTAssertEqual(note.quizQuestions?.count, 1)
    }
    func testNoteRoundTripKeepsStudyMaterial() throws {
        let note = NoteItem(_id: "fixture", title: "Test", flashcards: [.init(front: "Q", back: "A")], quizQuestions: [.init(question: "Q", wrongAnswers: ["B"], correctAnswer: "A")])
        XCTAssertEqual(try JSONDecoder().decode(NoteItem.self, from: JSONEncoder().encode(note)), note)
    }
}
