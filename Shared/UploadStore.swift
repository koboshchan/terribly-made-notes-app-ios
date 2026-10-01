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

    public var progress: Double {
        totalBytes > 0 ? min(1, Double(bytesSent) / Double(totalBytes)) : 0
    }
}

public final class UploadStore: @unchecked Sendable {
    public static let shared = UploadStore()
    public static let appGroup = "group.com.kobosh.notes"

    private let lock = NSLock()
    public let directory: URL
    private var recordsURL: URL { directory.appendingPathComponent("records.json") }

    private init() {
        let fm = FileManager.default
        let base = fm.containerURL(forSecurityApplicationGroupIdentifier: UploadStore.appGroup)
            ?? fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        directory = base.appendingPathComponent("Uploads", isDirectory: true)
        try? fm.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    public func all() -> [UploadRecord] {
        lock.lock(); defer { lock.unlock() }
        return readUnlocked()
    }

    public func record(id: String) -> UploadRecord? {
        all().first { $0.id == id }
    }

    public func upsert(_ record: UploadRecord) {
        mutate { records in
            if let i = records.firstIndex(where: { $0.id == record.id }) {
                records[i] = record
            } else {
                records.append(record)
            }
        }
    }

    public func update(id: String, _ change: (inout UploadRecord) -> Void) {
        mutate { records in
            if let i = records.firstIndex(where: { $0.id == id }) { change(&records[i]) }
        }
    }

    public func bodyURL(for record: UploadRecord) -> URL {
        directory.appendingPathComponent(record.bodyPath)
    }

    /// Deletes staged bodies of completed uploads and drops finished records
    /// older than a week.
    public func prune() {
        let cutoff = Date().addingTimeInterval(-7 * 24 * 3600)
        mutate { records in
            for r in records where r.status == .completed {
                try? FileManager.default.removeItem(at: self.directory.appendingPathComponent(r.bodyPath))
            }
            records.removeAll { r in
                (r.status == .completed || r.status == .failed) && r.createdAt < cutoff
            }
        }
    }

    /// Wipes every queued upload (sign-out).
    public func clearAll() {
        lock.lock(); defer { lock.unlock() }
        let items = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for item in items { try? FileManager.default.removeItem(at: item) }
    }

    private func mutate(_ body: (inout [UploadRecord]) -> Void) {
        lock.lock(); defer { lock.unlock() }
        var records = readUnlocked()
        body(&records)
        let enc = JSONEncoder()
        enc.dateEncodingStrategy = .iso8601
        if let data = try? enc.encode(records) {
            try? data.write(to: recordsURL, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        }
    }

    private func readUnlocked() -> [UploadRecord] {
        // NOTE: cross-process writes are last-writer-wins (no file coordination).
        // Each process mostly touches records it created, which is acceptable for now.
        guard let data = try? Data(contentsOf: recordsURL) else { return [] }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        return (try? dec.decode([UploadRecord].self, from: data)) ?? []
    }
}
