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
