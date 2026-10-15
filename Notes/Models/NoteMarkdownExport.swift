import CoreTransferable
import Foundation
import UniformTypeIdentifiers

/// In-memory export avoids leaving private notes in a shared temporary directory.
struct NoteMarkdownExport: Transferable, Sendable {
    let note: NoteItem

    var filename: String {
        let safe = note.title.components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .filter { !$0.isEmpty }.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        return String((safe.isEmpty ? "Note" : safe).prefix(80)) + ".md"
    }

    var text: String {
        var sections = ["# \(note.title)"]
        if let description = note.description, !description.isEmpty { sections.append(description) }
        if let content = note.content, !content.isEmpty { sections.append(content) }
        if let cards = note.flashcards, !cards.isEmpty {
            sections.append("## Flashcards\n\n" + cards.map { "**Q:** \($0.front)\n\n**A:** \($0.back)" }.joined(separator: "\n\n"))
        }
        if let questions = note.quizQuestions, !questions.isEmpty {
            sections.append("## Quiz\n\n" + questions.enumerated().map { index, question in
                var text = "\(index + 1). \(question.question)\n\nAnswer: \(question.correctAnswer)"
                if let explanation = question.explanation, !explanation.isEmpty { text += "\n\n" + explanation }
                return text
            }.joined(separator: "\n\n"))
        }
        return sections.joined(separator: "\n\n") + "\n"
    }

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: .init(filenameExtension: "md") ?? .plainText) { value in
            Data(value.text.utf8)
        }
        .suggestedFileName { $0.filename }
    }
}
