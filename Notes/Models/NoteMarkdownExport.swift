import Foundation

/// Markdown export matching the web app's "Download Markdown" action:
/// notes content, then flashcards and quiz.
enum NoteMarkdownExport {
    static func markdown(for note: NoteItem) -> String {
        var out = "# \(note.title)\n\n"
        if let cls = note.noteClass, !cls.isEmpty { out += "_Class: \(cls)_\n\n" }
        if let content = note.content, !content.isEmpty { out += content + "\n\n" }

        if let cards = note.flashcards, !cards.isEmpty {
            out += "## Flashcards\n\n"
            for card in cards {
                out += "**Q:** \(card.front)\n\n**A:** \(card.back)\n\n"
            }
        }

        if let quiz = note.quizQuestions, !quiz.isEmpty {
            out += "## Quiz\n\n"
            for (i, q) in quiz.enumerated() {
                out += "\(i + 1). \(q.question)\n\n   Answer: \(q.correctAnswer)\n"
                if let explanation = q.explanation, !explanation.isEmpty { out += "   \(explanation)\n" }
                out += "\n"
            }
        }
        return out
    }

    /// Writes the export to a temp .md file for ShareLink / Files.
    static func file(for note: NoteItem) -> URL? {
        let safe = note.title.components(separatedBy: CharacterSet(charactersIn: "/\\?%*|\"<>:")).joined()
        let name = (safe.isEmpty ? "note" : String(safe.prefix(80))) + ".md"
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try markdown(for: note).write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }
}
