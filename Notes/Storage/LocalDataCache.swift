import Foundation

public final class LocalDataCache: Sendable {
    public static let shared = LocalDataCache()

    private let cacheDirectory: URL
    private let detailsDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    private init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let baseFolder = appSupport.appendingPathComponent("NotesCache", isDirectory: true)
        let detailsFolder = baseFolder.appendingPathComponent("details", isDirectory: true)

        try? fileManager.createDirectory(at: baseFolder, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: detailsFolder, withIntermediateDirectories: true)

        self.cacheDirectory = baseFolder
        self.detailsDirectory = detailsFolder

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    // MARK: - Notes List

    private var notesFileURL: URL {
        cacheDirectory.appendingPathComponent("notes_cache.json")
    }

    public func loadNotes() -> [NoteItem]? {
        guard let data = try? Data(contentsOf: notesFileURL) else {
            return nil
        }
        return try? decoder.decode([NoteItem].self, from: data)
    }

    public func saveNotes(_ notes: [NoteItem]) {
        guard let data = try? encoder.encode(notes) else { return }
        try? data.write(to: notesFileURL, options: .atomic)

        // Also update individual cached details for fast offline access
        for note in notes {
            // Only update detail cache if we don't already have richer detail or to keep basic metadata current
            if let existing = loadNoteDetail(id: note.id) {
                // If existing has richer content (e.g. flashcards or quizzes), preserve it unless note has it
                let merged = mergeNote(existing: existing, incoming: note)
                saveNoteDetail(merged)
            } else {
                saveNoteDetail(note)
            }
        }
    }

    // MARK: - Classes List

    private var classesFileURL: URL {
        cacheDirectory.appendingPathComponent("classes_cache.json")
    }

    public func loadClasses() -> [UserClass]? {
        guard let data = try? Data(contentsOf: classesFileURL) else {
            return nil
        }
        return try? decoder.decode([UserClass].self, from: data)
    }

    public func saveClasses(_ classes: [UserClass]) {
        guard let data = try? encoder.encode(classes) else { return }
        try? data.write(to: classesFileURL, options: .atomic)
    }

    // MARK: - Individual Note Detail

    private func detailFileURL(id: String) -> URL {
        // Sanitize note id for filesystem
        let safeName = id.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        let filename = safeName.isEmpty ? "note" : safeName
        return detailsDirectory.appendingPathComponent("\(filename).json")
    }

    public func loadNoteDetail(id: String) -> NoteItem? {
        let file = detailFileURL(id: id)
        guard let data = try? Data(contentsOf: file) else {
            return nil
        }
        return try? decoder.decode(NoteItem.self, from: data)
    }

    public func saveNoteDetail(_ note: NoteItem) {
        let file = detailFileURL(id: note.id)
        guard let data = try? encoder.encode(note) else { return }
        try? data.write(to: file, options: .atomic)
    }

    public func removeNote(id: String) {
        let file = detailFileURL(id: id)
        try? FileManager.default.removeItem(at: file)

        if var cachedNotes = loadNotes() {
            cachedNotes.removeAll { $0.id == id }
            saveNotes(cachedNotes)
        }
    }

    // MARK: - Helpers

    private func mergeNote(existing: NoteItem, incoming: NoteItem) -> NoteItem {
        let title = incoming.title.isEmpty ? existing.title : incoming.title
        let description = incoming.description ?? existing.description
        let content = (incoming.content?.isEmpty == false) ? incoming.content : existing.content
        let originalFileName = incoming.originalFileName ?? existing.originalFileName
        let noteClass = incoming.noteClass ?? existing.noteClass
        let error = incoming.error ?? existing.error
        let flashcards = (incoming.flashcards?.isEmpty == false) ? incoming.flashcards : existing.flashcards
        let quizQuestions = (incoming.quizQuestions?.isEmpty == false) ? incoming.quizQuestions : existing.quizQuestions
        let duration = incoming.duration ?? existing.duration
        let createdAt = incoming.createdAt ?? existing.createdAt

        return NoteItem(
            _id: incoming._id,
            title: title,
            description: description,
            content: content,
            status: incoming.status,
            originalFileName: originalFileName,
            noteClass: noteClass,
            error: error,
            flashcards: flashcards,
            quizQuestions: quizQuestions,
            createdAt: createdAt,
            duration: duration
        )
    }
}
