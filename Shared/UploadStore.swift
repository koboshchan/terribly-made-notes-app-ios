import Foundation

/// Durable record of one audio upload, persisted in the app group container
/// so the app and the share extension see the same queue and nothing is lost
/// if either process is suspended or killed mid-upload.
public struct UploadRecord: Codable, Identifiable, Sendable, Equatable {
    public enum Status: String, Codable, Sendable {
        case pending      // staged, not started
        case uploading    // handed to the background URLSession
        case needsAuth    // waiting for a fresh session from the main app
        case completed
        case failed
    }

    /// Also sent as the Idempotency-Key header, so a retry of an uncertain
    /// upload can be de-duplicated server side.
    public let id: String
    public var displayName: String
    public var bodyPath: String          // staged multipart body, relative to the uploads dir
    public var boundary: String
    public var fields: [String: String]  // multipart text fields (language, className, ...)
    public var status: Status
    public var noteId: String?
    public var bytesSent: Int64
    public var totalBytes: Int64
    public var error: String?
    public var attempts: Int
    public let createdAt: Date
    /// Who staged this upload and for which server. Optional so records
    /// written by older builds still decode; those are treated as unowned and
    /// never resumed with a different account's token.
    public var ownerUserId: String?
    public var server: String?

    /// True only if the record was staged by `userId` against `server`.
    public func belongs(to userId: String?, server: URL) -> Bool {
        guard let ownerUserId, let userId, let recordServer = self.server else { return false }
        return ownerUserId == userId && recordServer == server.absoluteString
    }

    public var progress: Double {
        totalBytes > 0 ? min(1, Double(bytesSent) / Double(totalBytes)) : 0
    }
}

public final class UploadStore: @unchecked Sendable {
    public static let shared = UploadStore()
    public static let appGroup = "group.com.kobosh.notes"

    private let lock = NSLock()
    public let directory: URL
    /// One JSON file per record. The app and the share extension each mostly
    /// write their own records, so per-record atomic files plus file
    /// coordination avoid one process overwriting the other's whole queue.
    private let recordsDir: URL
    private var legacyRecordsURL: URL { directory.appendingPathComponent("records.json") }

    private init() {
        let fm = FileManager.default
        let base = fm.containerURL(forSecurityApplicationGroupIdentifier: UploadStore.appGroup)
            ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("Uploads", isDirectory: true)
        recordsDir = directory.appendingPathComponent("records", isDirectory: true)
        try? fm.createDirectory(at: recordsDir, withIntermediateDirectories: true,
                                attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        Self.excludeFromBackup(directory)
        migrateLegacyFile()
    }

    static func excludeFromBackup(_ url: URL) {
        var url = url
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e
    }()
    private static let decoder: JSONDecoder = {
        let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d
    }()

    private func fileURL(id: String) -> URL {
        let safe = id.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        return recordsDir.appendingPathComponent("\(safe).json")
    }

    // MARK: - Reads

    public func all() -> [UploadRecord] {
        let files = (try? FileManager.default.contentsOfDirectory(at: recordsDir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "json" }
            .compactMap { readCoordinated($0) }
            .sorted { $0.createdAt < $1.createdAt }
    }

    public func record(id: String) -> UploadRecord? {
        readCoordinated(fileURL(id: id))
    }

    // MARK: - Writes

    public func upsert(_ record: UploadRecord) {
        lock.lock(); defer { lock.unlock() }
        coordinate(fileURL(id: record.id)) { url in
            self.writeUnlocked(record, to: url)
        }
    }

    /// Read-modify-write of one record under a coordinated write, so a
    /// concurrent update from the other process is not lost.
    public func update(id: String, _ change: (inout UploadRecord) -> Void) {
        lock.lock(); defer { lock.unlock() }
        coordinate(fileURL(id: id)) { url in
            guard var record = self.decode(url) else { return }
            change(&record)
            self.writeUnlocked(record, to: url)
        }
    }

    public func remove(id: String) {
        lock.lock(); defer { lock.unlock() }
        if let r = decode(fileURL(id: id)) {
            try? FileManager.default.removeItem(at: bodyURL(for: r))
        }
        coordinate(fileURL(id: id)) { try? FileManager.default.removeItem(at: $0) }
    }

    public func bodyURL(for record: UploadRecord) -> URL {
        directory.appendingPathComponent(record.bodyPath)
    }

    /// Deletes staged bodies of completed uploads and drops finished records
    /// older than a week.
    public func prune() {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        for r in all() {
            if r.status == .completed {
                try? FileManager.default.removeItem(at: bodyURL(for: r))
            }
            if (r.status == .completed || r.status == .failed) && r.createdAt < cutoff {
                remove(id: r.id)
            }
        }
    }

    /// Wipes every queued upload (sign-out). Callers must cancel in-flight
    /// URLSession tasks first (see BackgroundUploader.cancelAll).
    public func clearAll() {
        lock.lock(); defer { lock.unlock() }
        coordinate(directory) { dir in
            let items = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
            for item in items { try? FileManager.default.removeItem(at: item) }
        }
        try? FileManager.default.createDirectory(at: recordsDir, withIntermediateDirectories: true,
                                                 attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
    }

    // MARK: - Helpers

    private func coordinate(_ url: URL, _ body: (URL) -> Void) {
        var error: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(writingItemAt: url, options: [], error: &error) { body($0) }
        if let error { print("UploadStore coordination failed: \(error.localizedDescription)") }
    }

    private func readCoordinated(_ url: URL) -> UploadRecord? {
        var result: UploadRecord?
        var error: NSError?
        NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &error) {
            result = self.decode($0)
        }
        return result
    }

    private func decode(_ url: URL) -> UploadRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? Self.decoder.decode(UploadRecord.self, from: data)
    }

    private func writeUnlocked(_ record: UploadRecord, to url: URL) {
        guard let data = try? Self.encoder.encode(record) else { return }
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        } catch {
            print("UploadStore write failed: \(error.localizedDescription)")
        }
    }

    /// Splits the old single records.json into per-record files.
    private func migrateLegacyFile() {
        guard let data = try? Data(contentsOf: legacyRecordsURL),
              let records = try? Self.decoder.decode([UploadRecord].self, from: data) else { return }
        for r in records { writeUnlocked(r, to: fileURL(id: r.id)) }
        try? FileManager.default.removeItem(at: legacyRecordsURL)
    }
}
