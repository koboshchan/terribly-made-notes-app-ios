import Foundation
import ClerkKit

public enum APIError: LocalizedError, Sendable {
    case notSignedIn
    case network(String)
    case server(String)
    case decoding(String)
    case invalidResponse
    case fileNotFound

    public var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "You are not signed in. Please sign in to continue."
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
        guard let token = try await Clerk.shared.session?.getToken() else {
            throw APIError.notSignedIn
        }

        UserDefaults(suiteName: "group.com.kobosh.notes")?.setValue(token, forKey: "clerkToken")

        let fullURL = AppConfig.baseURL.appendingPathComponent(path)
        var request = URLRequest(url: fullURL)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
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

        guard (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(APIErrorPayload.self, from: data))?.error
            throw APIError.server(message ?? "Request failed (HTTP \(http.statusCode))")
        }

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

        guard (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(APIErrorPayload.self, from: data))?.error
            throw APIError.server(message ?? "Request failed (HTTP \(http.statusCode))")
        }
    }

    // MARK: - Notes Endpoints

    public static func fetchNotes(search: String? = nil, sortBy: String = "uploaded", sortOrder: String = "desc") async throws -> [NoteItem] {
        var components = URLComponents(url: AppConfig.baseURL.appendingPathComponent("/api/notes"), resolvingAgainstBaseURL: true)!
        var queryItems = [
            URLQueryItem(name: "sortBy", value: sortBy),
            URLQueryItem(name: "sortOrder", value: sortOrder)
        ]
        if let search, !search.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            queryItems.append(URLQueryItem(name: "search", value: search))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            throw APIError.invalidResponse
        }

        guard let token = try await Clerk.shared.session?.getToken() else {
            throw APIError.notSignedIn
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

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
        guard (200..<300).contains(http.statusCode) else {
            let message = (try? decoder.decode(APIErrorPayload.self, from: data))?.error
            throw APIError.server(message ?? "Request failed (HTTP \(http.statusCode))")
        }

        if let direct = try? decoder.decode([NoteItem].self, from: data) {
            return direct
        }

        if let lossy = try? decoder.decode([LossyItem<NoteItem>].self, from: data) {
            return lossy.compactMap(\.value)
        }

        do {
            return try decoder.decode([NoteItem].self, from: data)
        } catch {
            throw APIError.decoding(error.localizedDescription)
        }
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
        let didStartAccessing = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didStartAccessing {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }

        guard let fileData = try? Data(contentsOf: fileURL) else {
            throw APIError.fileNotFound
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var request = try await authorizedRequest(path: "/api/upload", method: "POST")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let filename = fileURL.lastPathComponent
        let mimeType = mimeTypeFor(url: fileURL)

        var body = Data()

        // Append language field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("\(language)\r\n".data(using: .utf8)!)

        // Append file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)

        // Close multipart boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let uploadRes: UploadResponse = try await send(request)

        // If a class was chosen, assign the note to the class
        if let noteClass, !noteClass.isEmpty {
            try? await updateNoteClass(id: uploadRes.noteId, noteClass: noteClass)
        }

        return uploadRes.noteId
    }

    private static func mimeTypeFor(url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        switch ext {
        case "m4a": return "audio/m4a"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "aac": return "audio/aac"
        case "flac": return "audio/flac"
        case "ogg": return "audio/ogg"
        default: return "audio/m4a"
        }
    }
}
