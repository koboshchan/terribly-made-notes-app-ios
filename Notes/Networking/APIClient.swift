import Foundation
import ClerkKit

public enum APIError: LocalizedError, Sendable {
    case notSignedIn
    case sessionExpired
    case network(String)
    case server(String)
    case decoding(String)
    case invalidResponse
    case fileNotFound

    public var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "You are not signed in. Please sign in to continue."
        case .sessionExpired:
            return "Your session expired. Please sign in again."
        case .network(let message):
            return "Internet is not reachable: \(message)"
        case .server(let message):
            return message
        case .decoding(let message):
            return "Failed to parse data from the server: \(message)"
        case .invalidResponse:
            return "Unexpected response from the server."
        case .fileNotFound:
            return "The selected audio file could not be read."
        }
    }

    public var isNetworkError: Bool {
        if case .network = self { return true }
        return false
    }
}

private struct APIErrorPayload: Decodable {
    let error: String?
}

private struct UploadResponse: Decodable {
    let noteId: String
    let message: String?
}

private struct ChatResponse: Decodable {
    let message: String
}

private struct LossyItem<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.value = try? container.decode(T.self)
    }
}

public enum APIClient {
    private static let decoder: JSONDecoder = {
        let dec = JSONDecoder()
        return dec
    }()

    private static let encoder: JSONEncoder = JSONEncoder()

    // MARK: - Core Request Builder

    public static func authorizedRequest(path: String, method: String = "GET") async throws -> URLRequest {
        let fullURL = AppConfig.baseURL.appendingPathComponent(path)
        return try await authorizedRequest(url: fullURL, method: method)
    }

    public static func authorizedRequest(url fullURL: URL, method: String = "GET") async throws -> URLRequest {
        let token = try await currentToken()
        var request = URLRequest(url: fullURL)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    /// Fetches a fresh Clerk token and mirrors it to the shared Keychain so the
    /// share extension can use it while it is still valid.
    static func currentToken() async throws -> String {
        guard let session = Clerk.shared.session else { throw APIError.notSignedIn }
        guard let token = try await session.getToken() else { throw APIError.sessionExpired }
        do {
            try SharedAuthStore.save(token: token, userId: Clerk.shared.user?.id)
        } catch {
            // The app itself can continue; only the share extension loses access.
            print("Shared session mirror failed: \(error.localizedDescription)")
        }
        return token
    }

    static func checkStatus(_ http: HTTPURLResponse, data: Data) throws {
        if http.statusCode == 401 { throw APIError.sessionExpired }
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(APIErrorPayload.self, from: data))?.error
            throw APIError.server(message ?? "Request failed (HTTP \(http.statusCode))")
        }
    }

    private static func send<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlErr as URLError {
            throw APIError.network(urlErr.localizedDescription)
        } catch {
            throw APIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        try checkStatus(http, data: data)

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            let bodySnippet = String(data: data.prefix(500), encoding: .utf8) ?? ""
            print("Decoding failed for \(T.self): \(error)\nSnippet: \(bodySnippet)")
            throw APIError.decoding(error.localizedDescription)
        }
    }

    private static func sendVoid(_ request: URLRequest) async throws {
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let urlErr as URLError {
            throw APIError.network(urlErr.localizedDescription)
        } catch {
            throw APIError.network(error.localizedDescription)
        }

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        try checkStatus(http, data: data)
    }

    // MARK: - Notes Endpoints

    public struct NotesPage: Sendable {
        public let notes: [NoteItem]
        public let hasMore: Bool
    }

    /// One page of note summaries (server default and max page size 50/100;
    /// content and study material are not included).
    public static func fetchNotesPage(
        page: Int,
        limit: Int = 50,
        search: String? = nil,
        sortBy: String = "uploaded",
        sortOrder: String = "desc"
    ) async throws -> NotesPage {
        var components = URLComponents(url: AppConfig.baseURL.appendingPathComponent("/api/notes"), resolvingAgainstBaseURL: true)!
        var queryItems = [
            URLQueryItem(name: "sortBy", value: sortBy),
            URLQueryItem(name: "sortOrder", value: sortOrder),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "limit", value: String(limit))
        ]
        if let search, !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "search", value: search))
        }
        components.queryItems = queryItems
        guard let url = components.url else { throw APIError.invalidResponse }

        let request = try await authorizedRequest(url: url)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw APIError.network(error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else { throw APIError.invalidResponse }
        try checkStatus(http, data: data)

        let hasMore = http.value(forHTTPHeaderField: "X-Has-More")?.lowercased() == "true"
        let notes: [NoteItem]
        if let direct = try? decoder.decode([NoteItem].self, from: data) {
            notes = direct
        } else if let lossy = try? decoder.decode([LossyItem<NoteItem>].self, from: data) {
            notes = lossy.compactMap(\.value)
        } else {
            throw APIError.decoding("Could not decode notes page")
        }
        return NotesPage(notes: notes, hasMore: hasMore)
    }

    /// Fetches every page. The result is a complete list, so callers may
    /// reconcile deletions against it. Throws if any page fails (a partial
    /// list must never be treated as complete).
    public static func fetchNotes(search: String? = nil, sortBy: String = "uploaded", sortOrder: String = "desc") async throws -> [NoteItem] {
        var all: [NoteItem] = []
        var seen = Set<String>()
        var page = 0
        while true {
            try Task.checkCancellation()
            let result = try await fetchNotesPage(page: page, limit: 100, search: search, sortBy: sortBy, sortOrder: sortOrder)
            for note in result.notes where seen.insert(note.id).inserted { all.append(note) }
            guard result.hasMore, !result.notes.isEmpty, page < 500 else { break }
            page += 1
        }
        return all
    }

    public static func fetchNote(id: String) async throws -> NoteItem {
        let request = try await authorizedRequest(path: "/api/notes/\(id)")
        return try await send(request)
    }

    public static func deleteNote(id: String) async throws {
        let request = try await authorizedRequest(path: "/api/notes/\(id)", method: "DELETE")
        try await sendVoid(request)
    }

    public static func retryNote(id: String) async throws {
        let request = try await authorizedRequest(path: "/api/notes/\(id)/retry", method: "POST")
        try await sendVoid(request)
    }

    public static func updateNoteClass(id: String, noteClass: String?) async throws {
        var request = try await authorizedRequest(path: "/api/notes/\(id)", method: "PATCH")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String?] = ["class": noteClass]
        request.httpBody = try encoder.encode(body)
        try await sendVoid(request)
    }

    /// Edits title and/or Markdown content (server rejects while processing).
    public static func updateNote(id: String, title: String?, content: String?) async throws {
        var request = try await authorizedRequest(path: "/api/notes/\(id)", method: "PATCH")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: String] = [:]
        if let title { body["title"] = title }
        if let content { body["content"] = content }
        request.httpBody = try encoder.encode(body)
        try await sendVoid(request)
    }

    /// Saves a corrected transcript.
    public static func updateTranscript(id: String, transcript: String) async throws {
        var request = try await authorizedRequest(path: "/api/notes/\(id)/transcript", method: "PATCH")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(["transcript": transcript])
        try await sendVoid(request)
    }

    // MARK: - Sharing

    public struct ShareInfo: Decodable, Sendable {
        public let shareUrl: String?
        public let shareEnabled: Bool?
        public let shareExpiresAt: String?
        public let shareAllowChat: Bool?
    }

    private struct ShareBody: Encodable {
        let expiresInDays: Int
        let allowChat: Bool
        let rotate: Bool?
    }

    public static func fetchShare(id: String) async throws -> ShareInfo {
        try await send(try await authorizedRequest(path: "/api/notes/\(id)/share"))
    }

    /// Creates (or updates) the read-only link. `rotate` issues a new token,
    /// invalidating the old URL.
    public static func createShare(id: String, expiresInDays: Int = 30, allowChat: Bool = false, rotate: Bool = false) async throws -> ShareInfo {
        var request = try await authorizedRequest(path: "/api/notes/\(id)/share", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(ShareBody(expiresInDays: expiresInDays, allowChat: allowChat, rotate: rotate ? true : nil))
        return try await send(request)
    }

    public static func revokeShare(id: String) async throws {
        try await sendVoid(try await authorizedRequest(path: "/api/notes/\(id)/share", method: "DELETE"))
    }

    public static func fetchTranscript(id: String) async throws -> String {
        let request = try await authorizedRequest(path: "/api/notes/\(id)/transcript")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw APIError.server("Failed to fetch transcript")
        }
        guard let text = String(data: data, encoding: .utf8) else {
            throw APIError.decoding("Non-UTF8 string data")
        }
        return text
    }

    public static func fetchProgress(id: String) async throws -> NoteProgress {
        let request = try await authorizedRequest(path: "/api/notes/\(id)/progress")
        return try await send(request)
    }

    public static func chatWithNote(id: String, message: String, history: [ChatMessage]) async throws -> String {
        var request = try await authorizedRequest(path: "/api/notes/\(id)/chat", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        struct ChatHistoryItem: Encodable {
            let role: String
            let content: String
        }

        struct ChatRequestBody: Encodable {
            let message: String
            let history: [ChatHistoryItem]
        }

        let body = ChatRequestBody(
            message: message,
            history: history.map { ChatHistoryItem(role: $0.role, content: $0.content) }
        )
        request.httpBody = try encoder.encode(body)

        let response: ChatResponse = try await send(request)
        return response.message
    }

    // MARK: - User Classes Endpoints

    public static func fetchClasses() async throws -> [UserClass] {
        let request = try await authorizedRequest(path: "/api/user/classes")
        return try await send(request)
    }

    public static func createClass(name: String, description: String? = nil) async throws -> UserClass {
        var request = try await authorizedRequest(path: "/api/user/classes", method: "POST")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        let body: [String: String?] = ["name": name, "description": description]
        request.httpBody = try encoder.encode(body)
        return try await send(request)
    }

    public static func deleteClass(id: String) async throws {
        let request = try await authorizedRequest(path: "/api/user/classes/\(id)", method: "DELETE")
        try await sendVoid(request)
    }

    // MARK: - Audio Upload (Multipart Form Data)

    public static func uploadAudio(
        fileURL: URL,
        language: String = "english",
        noteClass: String? = nil
    ) async throws -> String {
        let record: UploadRecord
        do {
            record = try BackgroundUploader.stage(
                audioFile: fileURL,
                displayName: fileURL.lastPathComponent,
                fields: uploadFields(language: language, noteClass: noteClass),
                ownerUserId: Clerk.shared.user?.id,
                server: AppConfig.baseURL
            )
        } catch {
            throw APIError.fileNotFound
        }

        let token = try await currentToken()
        let noteId: String
        do {
            noteId = try await BackgroundUploader.shared(identifier: BackgroundUploader.appSessionID)
                .upload(recordId: record.id, token: token, userId: Clerk.shared.user?.id, baseURL: AppConfig.baseURL)
        } catch let err as UploadServerError {
            throw err.statusCode == 401 ? APIError.sessionExpired : APIError.server(err.message)
        } catch {
            throw APIError.network(error.localizedDescription)
        }
        return noteId
    }

    /// The server reads `className` from the upload form and stores it with
    /// classificationSource = "manual", so the class is set atomically instead
    /// of with a follow-up PATCH whose failure used to be swallowed.
    static func uploadFields(language: String, noteClass: String?) -> [String: String] {
        var fields = ["language": language]
        if let noteClass, !noteClass.isEmpty { fields["className"] = noteClass }
        return fields
    }

    /// Restarts queued uploads (from the share extension, an expired session,
    /// or a process that died mid-upload). Safe to call repeatedly: records in
    /// flight are skipped and the Idempotency-Key is reused.
    public static func resumeQueuedUploads() async {
        let store = UploadStore.shared
        store.prune()
        let candidates = store.all().filter { [.pending, .needsAuth, .uploading].contains($0.status) }
        guard !candidates.isEmpty, let token = try? await currentToken() else { return }
        let userId = Clerk.shared.user?.id
        let uploader = BackgroundUploader.shared(identifier: BackgroundUploader.appSessionID)
        for record in candidates {
            // start() refuses (and marks failed) records owned by another account/server.
            uploader.start(recordId: record.id, token: token, userId: userId, baseURL: AppConfig.baseURL)
        }
    }
}
