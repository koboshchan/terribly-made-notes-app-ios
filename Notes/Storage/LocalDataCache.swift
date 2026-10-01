import Foundation

/// Offline cache, partitioned per signed-in user and API server so one
/// account never sees another's notes on a shared device. Files are written
/// with data protection, excluded from backups, and wiped on sign-out.
public final class LocalDataCache: @unchecked Sendable {
    public static let shared = LocalDataCache()

    private let rootDirectory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private let lock = NSLock()
    private var scopeKey: String?

    private static let writeOptions: Data.WritingOptions = [.atomic, .completeFileProtectionUntilFirstUserAuthentication]

    private init() {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        var baseFolder = appSupport.appendingPathComponent("NotesCache", isDirectory: true)
        try? fileManager.createDirectory(at: baseFolder, withIntermediateDirectories: true)

        // Drop the old unscoped cache from earlier builds.
        for legacy in ["notes_cache.json", "classes_cache.json", "details"] {
            try? fileManager.removeItem(at: baseFolder.appendingPathComponent(legacy))
        }

        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? baseFolder.setResourceValues(values)
        self.rootDirectory = baseFolder

        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        self.encoder = enc

        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        self.decoder = dec
    }

    // MARK: - Scope

    /// Selects the cache partition. Pass nil to disable all reads and writes.
    public func setScope(userId: String?, server: URL = AppConfig.baseURL) {
        lock.lock(); defer { lock.unlock() }
        guard let userId, !userId.isEmpty else { scopeKey = nil; return }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-."))
        func clean(_ s: String) -> String { String(s.unicodeScalars.filter { allowed.contains($0) }) }
        let key = "\(clean(server.host ?? "server"))_\(clean(userId))"
        scopeKey = key
        let dir = rootDirectory.appendingPathComponent(key, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir.appendingPathComponent("details", isDirectory: true),
                                                 withIntermediateDirectories: true)
    }

    private var cacheDirectory: URL? {
        lock.lock(); defer { lock.unlock() }
        return scopeKey.map { rootDirectory.appendingPathComponent($0, isDirectory: true) }
    }

    private var detailsDirectory: URL? {
        cacheDirectory?.appendingPathComponent("details", isDirectory: true)
    }

    /// Removes every cached partition (sign-out / account switch).
    public func clearAll() {
        setScope(userId: nil)
        let items = (try? FileManager.default.contentsOfDirectory(at: rootDirectory, includingPropertiesForKeys: nil)) ?? []
        for item in items { try? FileManager.default.removeItem(at: item) }
    }

    // MARK: - Notes List

    private var notesFileURL: URL? {
        cacheDirectory?.appendingPathComponent("notes_cache.json")
    }

    public func loadNotes() -> [NoteItem]? {
        guard let url = notesFileURL, let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decoder.decode([NoteItem].self, from: data)
    }

    public func saveNotes(_ notes: [NoteItem]) {
        guard let url = notesFileURL, let data = try? encoder.encode(notes) else { return }
        try? data.write(to: url, options: Self.writeOptions)

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

    private var classesFileURL: URL? {
        cacheDirectory?.appendingPathComponent("classes_cache.json")
    }

    public func loadClasses() -> [UserClass]? {
        guard let url = classesFileURL, let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decoder.decode([UserClass].self, from: data)
    }

    public func saveClasses(_ classes: [UserClass]) {
        guard let url = classesFileURL, let data = try? encoder.encode(classes) else { return }
        try? data.write(to: url, options: Self.writeOptions)
    }

    // MARK: - Individual Note Detail

    private func detailFileURL(id: String) -> URL? {
        guard let detailsDirectory else { return nil }
        // Sanitize note id for filesystem
        let safeName = id.components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        let filename = safeName.isEmpty ? "note" : safeName
        return detailsDirectory.appendingPathComponent("\(filename).json")
    }

    public func loadNoteDetail(id: String) -> NoteItem? {
        guard let file = detailFileURL(id: id), let data = try? Data(contentsOf: file) else {
            return nil
        }
        return try? decoder.decode(NoteItem.self, from: data)
    }

    public func saveNoteDetail(_ note: NoteItem) {
        guard let file = detailFileURL(id: note.id), let data = try? encoder.encode(note) else { return }
        try? data.write(to: file, options: Self.writeOptions)
    }

    public func removeNote(id: String) {
        if let file = detailFileURL(id: id) {
            try? FileManager.default.removeItem(at: file)
        }

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
