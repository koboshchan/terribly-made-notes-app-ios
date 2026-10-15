import SwiftUI

@main
struct SharingHost: App {
    var body: some Scene {
        WindowGroup {
            NoteShareView(note: NoteItem(_id: "test", title: "Atomic structure", content: "Protons and neutrons form the nucleus.", flashcards: [.init(front: "What carries a negative charge?", back: "An electron")]))
                .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--dark") ? .dark : .light)
        }
    }
}

// Test-target-only API. Never linked into the real Notes app; no network or credentials.
enum APIError: LocalizedError {
    case notSignedIn, invalidResponse, network(String)
    var errorDescription: String? {
        switch self {
        case .notSignedIn: "You are not signed in."
        case .invalidResponse: "Unexpected response from the server."
        case .network(let message): message
        }
    }
}

@MainActor
enum APIClient {
    static var active = false
    static func fetchShare(id: String) async throws -> NoteShareInfo {
        if ProcessInfo.processInfo.arguments.contains("--error") { throw APIError.network("Could not load sharing settings. Try again.") }
        return NoteShareInfo(shareUrl: active ? "https://notes.kobosh.com/shared/test-link" : nil, shareEnabled: active, shareExpiresAt: nil, shareAllowChat: false)
    }
    static func createShare(id: String) async throws -> NoteShareInfo {
        active = true
        return try await fetchShare(id: id)
    }
    static func deleteShare(id: String) async throws { active = false }
}
