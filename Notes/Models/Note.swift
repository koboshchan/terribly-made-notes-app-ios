import Foundation

public struct Flashcard: Codable, Identifiable, Hashable, Sendable {
    public var id: String { front }
    public let front: String
    public let back: String

    public init(front: String, back: String) {
        self.front = front
        self.back = back
    }

    enum CodingKeys: String, CodingKey {
        case front
        case back
        case question
        case answer
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let frontVal = (try? container.decodeIfPresent(String.self, forKey: .front))
            ?? (try? container.decodeIfPresent(String.self, forKey: .question))
            ?? ""
        let backVal = (try? container.decodeIfPresent(String.self, forKey: .back))
            ?? (try? container.decodeIfPresent(String.self, forKey: .answer))
            ?? ""
        self.front = frontVal
        self.back = backVal
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(front, forKey: .front)
        try container.encode(back, forKey: .back)
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

    enum CodingKeys: String, CodingKey {
        case question
        case wrongAnswers
        case correctAnswer
        case explanation
        case hint
        case options
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.question = (try? container.decodeIfPresent(String.self, forKey: .question)) ?? ""
        let correct = (try? container.decodeIfPresent(String.self, forKey: .correctAnswer)) ?? ""
        self.correctAnswer = correct
        self.explanation = try? container.decodeIfPresent(String.self, forKey: .explanation)
        self.hint = try? container.decodeIfPresent(String.self, forKey: .hint)

        if let wrongs = try? container.decodeIfPresent([String].self, forKey: .wrongAnswers) {
            self.wrongAnswers = wrongs
        } else if let options = try? container.decodeIfPresent([String].self, forKey: .options) {
            self.wrongAnswers = options.filter { $0 != correct }
        } else {
            self.wrongAnswers = []
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(question, forKey: .question)
        try container.encode(wrongAnswers, forKey: .wrongAnswers)
        try container.encode(correctAnswer, forKey: .correctAnswer)
        try container.encodeIfPresent(explanation, forKey: .explanation)
        try container.encodeIfPresent(hint, forKey: .hint)
    }

    public var allOptions: [String] {
        var options = wrongAnswers
        if !correctAnswer.isEmpty {
            options.append(correctAnswer)
        }
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
        case id
        case title
        case description
        case content
        case status
        case originalFileName
        case noteClass
        case className = "class"
        case error
        case flashcards
        case quizQuestions
        case createdAt
        case recordedAt
        case duration
    }

    public init(
        _id: String,
        title: String,
        description: String? = nil,
        content: String? = nil,
        status: String = "completed",
        originalFileName: String? = nil,
        noteClass: String? = nil,
        error: String? = nil,
        flashcards: [Flashcard]? = nil,
        quizQuestions: [QuizQuestion]? = nil,
        createdAt: String? = nil,
        duration: Double? = nil
    ) {
        self._id = _id
        self.title = title
        self.description = description
        self.content = content
        self.status = status
        self.originalFileName = originalFileName
        self.noteClass = noteClass
        self.error = error
        self.flashcards = flashcards
        self.quizQuestions = quizQuestions
        self.createdAt = createdAt
        self.duration = duration
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // _id or id
        if let idStr = try? container.decodeIfPresent(String.self, forKey: ._id) {
            self._id = idStr
        } else if let idStr = try? container.decodeIfPresent(String.self, forKey: .id) {
            self._id = idStr
        } else {
            self._id = UUID().uuidString
        }

        // title
        let origName = try? container.decodeIfPresent(String.self, forKey: .originalFileName)
        self.originalFileName = origName
        if let t = try? container.decodeIfPresent(String.self, forKey: .title), !t.isEmpty {
            self.title = t
        } else {
            self.title = origName ?? "Untitled Note"
        }

        // description & content
        self.description = try? container.decodeIfPresent(String.self, forKey: .description)
        self.content = try? container.decodeIfPresent(String.self, forKey: .content)

        // status
        self.status = (try? container.decodeIfPresent(String.self, forKey: .status)) ?? "completed"

        // noteClass or class
        let nc = try? container.decodeIfPresent(String.self, forKey: .noteClass)
        let c = try? container.decodeIfPresent(String.self, forKey: .className)
        self.noteClass = nc ?? c

        // error
        self.error = try? container.decodeIfPresent(String.self, forKey: .error)

        // createdAt
        self.createdAt = try? container.decodeIfPresent(String.self, forKey: .createdAt)

        // duration (Double, Int, or String)
        if let d = try? container.decodeIfPresent(Double.self, forKey: .duration) {
            self.duration = d
        } else if let i = try? container.decodeIfPresent(Int.self, forKey: .duration) {
            self.duration = Double(i)
        } else if let s = try? container.decodeIfPresent(String.self, forKey: .duration), let d = Double(s) {
            self.duration = d
        } else {
            self.duration = nil
        }

        // flashcards: safely decode each element
        if let cardContainer = try? container.decodeIfPresent([SafeElement<Flashcard>].self, forKey: .flashcards) {
            self.flashcards = cardContainer.compactMap(\.value)
        } else {
            self.flashcards = nil
        }

        // quizQuestions: safely decode each element
        if let quizContainer = try? container.decodeIfPresent([SafeElement<QuizQuestion>].self, forKey: .quizQuestions) {
            self.quizQuestions = quizContainer.compactMap(\.value)
        } else {
            self.quizQuestions = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(_id, forKey: ._id)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(content, forKey: .content)
        try container.encode(status, forKey: .status)
        try container.encodeIfPresent(originalFileName, forKey: .originalFileName)
        try container.encodeIfPresent(noteClass, forKey: .noteClass)
        try container.encodeIfPresent(error, forKey: .error)
        try container.encodeIfPresent(flashcards, forKey: .flashcards)
        try container.encodeIfPresent(quizQuestions, forKey: .quizQuestions)
        try container.encodeIfPresent(createdAt, forKey: .createdAt)
        try container.encodeIfPresent(duration, forKey: .duration)
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

/// Helper to decode array elements losslessly skipping invalid items
private struct SafeElement<T: Decodable>: Decodable {
    let value: T?

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try? container.decode(T.self)
    }
}
