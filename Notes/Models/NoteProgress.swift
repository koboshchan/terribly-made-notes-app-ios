import Foundation

public struct NoteProgress: Codable, Sendable {
    public let message: String?
    public let percent: Int?
    public let step: Int?
    public let totalSteps: Int?
    public let status: String?
    public let error: String?

    public init(message: String? = nil, percent: Int? = nil, step: Int? = nil, totalSteps: Int? = nil, status: String? = nil, error: String? = nil) {
        self.message = message
        self.percent = percent
        self.step = step
        self.totalSteps = totalSteps
        self.status = status
        self.error = error
    }
}
