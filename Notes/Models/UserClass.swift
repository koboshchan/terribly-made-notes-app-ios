import Foundation

public struct UserClass: Codable, Identifiable, Hashable, Sendable {
    public var id: String { _id }
    public let _id: String
    public let name: String
    public let description: String?

    public init(_id: String, name: String, description: String? = nil) {
        self._id = _id
        self.name = name
        self.description = description
    }
}

/// Omits absent descriptions instead of encoding JSON null, which the API rejects.
struct ClassCreateRequest: Encodable {
    let name: String
    let description: String?

    init(name: String, description: String?) {
        self.name = name
        self.description = description.flatMap {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0
        }
    }
}
