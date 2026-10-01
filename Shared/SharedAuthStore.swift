import Foundation
import Security

/// Session token shared between the app and the share extension.
///
/// Stored in the Keychain under the app group access group instead of plain
/// UserDefaults. Clerk session JWTs are short lived, so the expiry is decoded
/// and checked; the extension never sends an expired token and instead queues
/// the upload for the main app.
public enum SharedAuthStore {
    public static let accessGroup = "group.com.kobosh.notes"
    private static let service = "com.kobosh.notes.session"
    private static let account = "clerkSessionToken"

    public struct Credential: Codable, Sendable {
        public let token: String
        public let userId: String?
        public let expiresAt: Date?

        /// Valid with a small safety margin for clock skew and upload start.
        public var isUsable: Bool {
            guard let expiresAt else { return true }
            return expiresAt.timeIntervalSinceNow > 15
        }
    }

    public static func save(token: String, userId: String?) {
        let credential = Credential(token: token, userId: userId, expiresAt: jwtExpiry(token))
        guard let data = try? JSONEncoder().encode(credential) else { return }

        let query = baseQuery()
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add.merge(attributes) { $1 }
            SecItemAdd(add as CFDictionary, nil)
        }
    }

    public static func load() -> Credential? {
        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(Credential.self, from: data)
    }

    public static func clear() {
        SecItemDelete(baseQuery() as CFDictionary)
        // Remove the legacy plaintext copy written by older builds.
        UserDefaults(suiteName: accessGroup)?.removeObject(forKey: "clerkToken")
    }

    private static func baseQuery() -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup
        ]
    }

    /// Reads `exp` from a JWT payload without verifying it (server verifies).
    static func jwtExpiry(_ token: String) -> Date? {
        let parts = token.split(separator: ".")
        guard parts.count >= 2 else { return nil }
        var b64 = String(parts[1]).replacingOccurrences(of: "-", with: "+").replacingOccurrences(of: "_", with: "/")
        while b64.count % 4 != 0 { b64 += "=" }
        guard let data = Data(base64Encoded: b64),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let exp = json["exp"] as? Double else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
