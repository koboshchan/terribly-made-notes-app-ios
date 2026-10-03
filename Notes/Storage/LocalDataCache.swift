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

    /// Bump when the on-disk format or merge semantics change; older files are ignored.
    static let schemaVersion = 2

    private struct Envelope<T: Codable>: Codable {
        let version: Int
        let savedAt: Date
        let value: T
    }

    private func encode<T: Codable>(_ value: T) -> Data? {
        try? encoder.encode(Envelope(version: Self.schemaVersion, savedAt: Date(), value: value))
    }

    private func decode<T: Codable>(_ type: T.Type, from data: Data) -> T? {
        guard let env = try? decoder.decode(Envelope<T>.self, from: data), env.version == Self.schemaVersion else { return nil }
        return env.value
    }

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
    func setScope(userId: String?, server: URL = AppConfig.baseURL) {
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
        return decode([NoteItem].self, from: data)
    }

    /// Saves the note list.
    ///
    /// `isComplete` must only be true when every page was fetched; only then
    /// are cached details for notes missing from the list deleted. A partial
    /// list (one page, or a polling update) never reconciles deletions.
    ///
    /// List entries are summaries (no content/study material), so they never
    /// overwrite a cached detail. A cached detail whose updatedAt or status no
    /// longer matches the summary is dropped so the detail view refetches
    /// instead of showing stale content. Full notes are stored as details.
    public func saveNotes(_ notes: [NoteItem], isComplete: Bool) {
        guard let url = notesFileURL, let data = encode(notes) else { return }
        try? data.write(to: url, options: Self.writeOptions)
        if isComplete {
            reconcileDetails(keeping: Set(notes.map(\.id)))
        }
        for note in notes {
            if !note.isSummary {
                saveNoteDetail(note)
            } else if let cached = loadNoteDetail(id: note.id),
                      cached.updatedAt != note.updatedAt || cached.status != note.status {
                removeDetailOnly(id: note.id)
            }
        }
    }

    private func removeDetailOnly(id: String) {
        guard let url = detailFileURL(id: id) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Classes List

    private var classesFileURL: URL? {
        cacheDirectory?.appendingPathComponent("classes_cache.json")
    }

    public func loadClasses() -> [UserClass]? {
        guard let url = classesFileURL, let data = try? Data(contentsOf: url) else {
            return nil
        }
        return decode([UserClass].self, from: data)
    }

    public func saveClasses(_ classes: [UserClass]) {
        guard let url = classesFileURL, let data = encode(classes) else { return }
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
        return decode(NoteItem.self, from: data)
    }

    /// Stores a full note from the detail endpoint, replacing (not merging)
    /// what was cached, so fields the server cleared are cleared here too.
    public func saveNoteDetail(_ note: NoteItem) {
        guard let file = detailFileURL(id: note.id), let data = encode(note) else { return }
        try? data.write(to: file, options: Self.writeOptions)
    }

    public func removeNote(id: String) {
        if let file = detailFileURL(id: id) {
            try? FileManager.default.removeItem(at: file)
        }

        if var cachedNotes = loadNotes() {
            cachedNotes.removeAll { $0.id == id }
            saveNotes(cachedNotes, isComplete: false)
        }
        if let t = transcriptFileURL(id: id) { try? FileManager.default.removeItem(at: t) }
    }

    // MARK: - Transcripts

    private func transcriptFileURL(id: String) -> URL? {
        detailFileURL(id: id).map { $0.deletingPathExtension().appendingPathExtension("transcript.json") }
    }

    public func loadTranscript(id: String) -> String? {
        guard let file = transcriptFileURL(id: id), let data = try? Data(contentsOf: file) else { return nil }
        return decode(String.self, from: data)
    }

    public func saveTranscript(_ text: String, id: String) {
        guard let file = transcriptFileURL(id: id), let data = encode(text) else { return }
        try? data.write(to: file, options: Self.writeOptions)
    }

    private func reconcileDetails(keeping ids: Set<String>) {
        guard let dir = detailsDirectory else { return }
        let keep = Set(ids.compactMap { detailFileURL(id: $0)?.deletingPathExtension().lastPathComponent })
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        for file in files {
            let stem = file.lastPathComponent.components(separatedBy: ".").first ?? ""
            if !keep.contains(stem) { try? FileManager.default.removeItem(at: file) }
        }
    }
}
