import Foundation

public struct ChatMessage: Codable, Identifiable, Hashable, Sendable {
    public let id: UUID
    public let role: String
    public let content: String

    public init(id: UUID = UUID(), role: String, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }

    public var isUser: Bool {
        role == "user"
    }
}
