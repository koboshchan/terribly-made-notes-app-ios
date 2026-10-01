import Foundation

/// Streams a multipart/form-data body to disk in fixed-size chunks so large
/// lectures never have to be loaded fully into memory.
public enum MultipartFileBuilder {
    public static func mimeType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "m4a": return "audio/m4a"
        case "mp3": return "audio/mpeg"
        case "wav": return "audio/wav"
        case "aac": return "audio/aac"
        case "flac": return "audio/flac"
        case "ogg": return "audio/ogg"
        default: return "audio/m4a"
        }
    }

    /// Writes the body to `destination` and returns its size in bytes.
    @discardableResult
    public static func build(
        audioFile: URL,
        fileName: String,
        fields: [String: String],
        boundary: String,
        destination: URL
    ) throws -> Int64 {
        let fm = FileManager.default
        try? fm.removeItem(at: destination)
        fm.createFile(atPath: destination.path, contents: nil,
                      attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        UploadStore.excludeFromBackup(destination)
        let out = try FileHandle(forWritingTo: destination)
        defer { try? out.close() }

        func write(_ string: String) throws { try out.write(contentsOf: Data(string.utf8)) }

        for key in fields.keys.sorted() {
            guard let value = fields[key] else { continue }
            try write("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(escape(key))\"\r\n\r\n\(value)\r\n")
        }

        try write("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"\(escape(fileName))\"\r\n")
        try write("Content-Type: \(mimeType(for: audioFile))\r\n\r\n")

        let input = try FileHandle(forReadingFrom: audioFile)
        defer { try? input.close() }
        while let chunk = try input.read(upToCount: 1 << 20), !chunk.isEmpty {
            try out.write(contentsOf: chunk)
        }

        try write("\r\n--\(boundary)--\r\n")
        return Int64(try out.offset())
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "\"", with: "%22").replacingOccurrences(of: "\r", with: "").replacingOccurrences(of: "\n", with: "")
    }
}
