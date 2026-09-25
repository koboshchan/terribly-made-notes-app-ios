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
        case uploading
        case completed
        case failed(String)
    }
}

public enum ShareUploader {
    private static let baseURL = URL(string: "https://notes.kobosh.com")!
    private static let appGroupSuite = "group.com.kobosh.notes"

    public static func storedAuthToken() -> String? {
        UserDefaults(suiteName: appGroupSuite)?.string(forKey: "clerkToken")
    }

    public static func upload(file: SharedAudioFile, token: String) async throws -> String {
        guard let fileData = try? Data(contentsOf: file.url) else {
            throw NSError(domain: "ShareExtension", code: 404, userInfo: [NSLocalizedDescriptionKey: "Could not read audio file: \(file.name)"])
        }

        let uploadURL = baseURL.appendingPathComponent("/api/upload")
        let boundary = "Boundary-\(UUID().uuidString)"

        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        let mimeType = mimeTypeFor(url: file.url)
        var body = Data()

        // Language parameter
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"language\"\r\n\r\n".data(using: .utf8)!)
        body.append("english\r\n".data(using: .utf8)!)

        // File payload
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(file.name)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)

        // Close multipart boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "ShareExtension", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid server response"])
        }

        guard (200..<300).contains(http.statusCode) else {
            struct ErrorResponse: Decodable { let error: String? }
            let errorMsg = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error
            throw NSError(domain: "ShareExtension", code: http.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMsg ?? "Upload failed (HTTP \(http.statusCode))"])
        }

        struct UploadResponse: Decodable { let noteId: String }
        let res = try JSONDecoder().decode(UploadResponse.self, from: data)
        return res.noteId
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
