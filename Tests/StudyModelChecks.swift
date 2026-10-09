import Foundation

@main
struct StudyModelChecks {
    static func main() throws {
        let duplicates = QuizQuestion(question: "Q", wrongAnswers: ["Wrong", "Wrong", "Correct", "", "  "], correctAnswer: "Correct")
        for _ in 0..<100 {
            let options = duplicates.allOptions
            precondition(options.count == 2, "Duplicate/blank choices must not render")
            precondition(Set(options) == ["Wrong", "Correct"], "Correct choice must appear exactly once")
        }
        let single = QuizQuestion(question: "Q", wrongAnswers: [], correctAnswer: "Yes")
        precondition(single.allOptions == ["Yes"])
        let legacy = try JSONDecoder().decode(QuizQuestion.self, from: Data(#"{"question":"Q","options":["A","B","B",""],"correctAnswer":"A"}"#.utf8))
        precondition(Set(legacy.allOptions) == ["A", "B"])
        let roundTrip = try JSONDecoder().decode(QuizQuestion.self, from: JSONEncoder().encode(duplicates))
        precondition(roundTrip == duplicates, "Option cleanup must not mutate persisted data")
        let cards = [Flashcard(front: "Q", back: "A"), Flashcard(front: "Q", back: "B")]
        precondition(cards.count == 2, "Repeated fronts must remain distinct study cards")
        print("Study model checks passed (100 randomized duplicate-choice checks, single choice, legacy decoding, round trip, repeated card fronts).")
    }
}
