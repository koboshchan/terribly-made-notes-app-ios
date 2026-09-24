import Foundation

public struct Flashcard: Codable, Identifiable, Hashable, Sendable {
    public var id: String { front }
    public let front: String
    public let back: String

    public init(front: String, back: String) {
        self.front = front
        self.back = back
    }
}

public struct QuizQuestion: Codable, Identifiable, Hashable, Sendable {
    public var id: String { question }
    public let question: String
    public let wrongAnswers: [String]
    public let correctAnswer: String
    public let explanation: String?
    public let hint: String?

    public init(question: String, wrongAnswers: [String], correctAnswer: String, explanation: String? = nil, hint: String? = nil) {
        self.question = question
        self.wrongAnswers = wrongAnswers
        self.correctAnswer = correctAnswer
        self.explanation = explanation
        self.hint = hint
    }

    /// Returns all options (wrong + correct) shuffled deterministically or randomly.
    public var allOptions: [String] {
        var options = wrongAnswers
        options.append(correctAnswer)
        return options.shuffled()
    }
}

public struct NoteItem: Codable, Identifiable, Hashable, Sendable {
    public var id: String { _id }
    public let _id: String
    public let title: String
    public let description: String?
    public let content: String?
    public let status: String
    public let originalFileName: String?
    public let noteClass: String?
    public let error: String?
    public let flashcards: [Flashcard]?
    public let quizQuestions: [QuizQuestion]?
    public let createdAt: String?
    public let duration: Double?

    enum CodingKeys: String, CodingKey {
        case _id
        case title
        case description
        case content
        case status
        case originalFileName
        case noteClass = "class"
        case error
        case flashcards
        case quizQuestions
        case createdAt
        case duration
    }

    public var isCompleted: Bool {
        status == "completed"
    }

    public var isProcessing: Bool {
        status == "processing" || status == "queued"
    }

    public var isError: Bool {
        status == "error"
    }

    public var formattedDate: String {
        guard let createdAt else { return "" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: createdAt) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        // Try fallback without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: createdAt) {
            return date.formatted(date: .abbreviated, time: .shortened)
        }
        return createdAt
    }

    public var formattedDuration: String? {
        guard let duration, duration > 0 else { return nil }
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}
