import Foundation

public struct SharedAudioFile: Identifiable, Sendable, Equatable {
    public let id: UUID
    public let name: String
    public let url: URL
    public var status: FileStatus

    public init(id: UUID = UUID(), name: String, url: URL, status: FileStatus = .pending) {
        self.id = id
        self.name = name
        self.url = url
        self.status = status
    }

    public enum FileStatus: Sendable, Equatable {
        case pending
        case uploading(Double)
        case queued       // staged; the main app finishes it after refreshing the session
        case completed
        case failed(String)
    }
}

public enum ShareUploader {
    private static let baseURL = URL(string: "https://notes.kobosh.com")!

    /// Returns the shared token only if it has not expired. Nil means the user
    /// must open the main app (signed out, or token too old to refresh here).
    public static func storedAuthToken() -> String? {
        guard let credential = SharedAuthStore.load(), credential.isUsable else { return nil }
        return credential.token
    }

    /// The extension has no picker, so it uses the language last chosen in
    /// the app (instead of always "english").
    public static var preferredLanguage: String {
        UserDefaults(suiteName: UploadStore.appGroup)?.string(forKey: "preferredLanguage") ?? "english"
    }

    public static var hasAnySession: Bool { SharedAuthStore.load() != nil }

    /// Stages the file on disk in the app group container (streamed, never
    /// loaded fully in memory) and returns the durable record.
    public static func stage(file: SharedAudioFile) throws -> UploadRecord {
        do {
            return try BackgroundUploader.stage(audioFile: file.url, displayName: file.name,
                                                fields: ["language": preferredLanguage],
                                                ownerUserId: SharedAuthStore.load()?.userId, server: baseURL)
        } catch {
            throw NSError(domain: "ShareExtension", code: 404, userInfo: [NSLocalizedDescriptionKey: "Could not read audio file: \(file.name)"])
        }
    }

    /// Marks a staged upload as waiting for the main app to supply a fresh token.
    public static func deferToApp(_ record: UploadRecord) {
        UploadStore.shared.update(id: record.id) { $0.status = .needsAuth }
    }

    /// Uploads on a background session, so the transfer survives the extension
    /// being dismissed; the containing app receives completion events.
    public static func upload(record: UploadRecord, token: String) async throws -> String {
        do {
            return try await BackgroundUploader.shared(identifier: BackgroundUploader.shareSessionID)
                .upload(recordId: record.id, token: token, userId: SharedAuthStore.load()?.userId, baseURL: baseURL)
        } catch let err as UploadServerError where err.statusCode == 401 {
            throw NSError(domain: "ShareExtension", code: 401, userInfo: [NSLocalizedDescriptionKey: "Session expired. Open Notes and the upload will finish automatically."])
        }
    }
}
