import Foundation
import Security

/// Session token shared between the app and the share extension.
///
/// Stored in the Keychain under a shared access group (declared in both
/// targets' `keychain-access-groups` entitlement). The group string needs the
/// team prefix, which is only known at build time, so it is read from the
/// `KeychainAccessGroup` Info.plist key (`$(AppIdentifierPrefix)group.com.kobosh.notes`).
///
/// Clerk session JWTs are short lived. A token whose expiry can't be decoded
/// is treated as unusable (fail closed).
public enum SharedAuthStore {
    public enum StoreError: LocalizedError {
        case missingAccessGroup
        case keychain(OSStatus)
        case encoding

        public var errorDescription: String? {
            switch self {
            case .missingAccessGroup: return "Keychain access group is not configured."
            case .keychain(let status): return "Keychain error \(status)."
            case .encoding: return "Could not encode session."
            }
        }
    }

    /// Fully resolved access group (team prefix + group id), or nil if the
    /// Info.plist key is missing or was not substituted at build time.
    public static let accessGroup: String? = {
        guard let value = Bundle.main.object(forInfoDictionaryKey: "KeychainAccessGroup") as? String,
              !value.isEmpty, !value.contains("$(") else { return nil }
        return value
    }()

    private static let service = "com.kobosh.notes.session"
    private static let account = "clerkSessionToken"
    private static let legacyDefaultsSuite = "group.com.kobosh.notes"

    public struct Credential: Codable, Sendable {
        public let token: String
        public let userId: String?
        public let expiresAt: Date?

        /// Fails closed: no decodable expiry means unusable. Keeps a small
        /// margin for clock skew and upload start.
        public var isUsable: Bool {
            guard let expiresAt else { return false }
            return expiresAt.timeIntervalSinceNow > 15
        }
    }

    @discardableResult
    public static func save(token: String, userId: String?) throws -> Credential {
        let credential = Credential(token: token, userId: userId, expiresAt: jwtExpiry(token))
        guard let data = try? JSONEncoder().encode(credential) else { throw StoreError.encoding }
        let query = try baseQuery()
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        var status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var add = query
            add.merge(attributes) { $1 }
            status = SecItemAdd(add as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw StoreError.keychain(status) }
        return credential
    }

    public static func load() -> Credential? {
        guard var query = try? baseQuery() else { return nil }
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else {
            if status != errSecItemNotFound { print("SharedAuthStore.load keychain status \(status)") }
            return nil
        }
        return try? JSONDecoder().decode(Credential.self, from: data)
    }

    public static func clear() throws {
        // Remove the legacy plaintext copy written by older builds.
        UserDefaults(suiteName: legacyDefaultsSuite)?.removeObject(forKey: "clerkToken")
        let status = SecItemDelete(try baseQuery() as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw StoreError.keychain(status) }
    }

    private static func baseQuery() throws -> [String: Any] {
        guard let accessGroup else { throw StoreError.missingAccessGroup }
        return [
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
              let exp = (json["exp"] as? NSNumber)?.doubleValue else { return nil }
        return Date(timeIntervalSince1970: exp)
    }
}
