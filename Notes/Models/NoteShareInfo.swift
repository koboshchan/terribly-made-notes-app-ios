import Foundation

/// Supports both main's URL-only response and the expanded sharing API in web PR #4.
struct NoteShareInfo: Decodable, Sendable {
    let shareUrl: String?
    let shareEnabled: Bool?
    let shareExpiresAt: String?
    let shareAllowChat: Bool?

    var expiration: Date? {
        guard let shareExpiresAt else { return nil }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: shareExpiresAt) ?? ISO8601DateFormatter().date(from: shareExpiresAt)
    }

    var activeURL: URL? {
        guard shareEnabled != false,
              expiration.map({ $0 > Date() }) ?? true,
              let shareUrl, let url = URL(string: shareUrl),
              url.scheme == "https", url.host != nil,
              url.user == nil, url.password == nil else { return nil }
        return url
    }
}
