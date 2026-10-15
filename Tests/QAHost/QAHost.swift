import SwiftUI

// Disposable test target only. No credentials, authentication override, or network.
@main
struct QAHost: App {
    init() { LocalDataCache.shared.removeNote(id: "fixture") }
    var body: some Scene {
        WindowGroup {
            NavigationStack {
                List {
                    NavigationLink("Welcome") { WelcomeView {} }
                    NavigationLink("Study note") { NoteDetailView(noteId: "fixture") }
                    NavigationLink("New recording") { RecordNoteView { _ in } }
                    NavigationLink("Classes") { ClassesView() }
                    NavigationLink("Empty flashcards") { FlashcardsView(flashcards: []) }
                    NavigationLink("Empty quiz") { QuizView(questions: []) }
                }.navigationTitle("Disposable QA")
            }
            .dynamicTypeSize(ProcessInfo.processInfo.arguments.contains("--large-text") ? .accessibility3 : .large)
            .preferredColorScheme(ProcessInfo.processInfo.arguments.contains("--dark") ? .dark : .light)
        }
    }
}

enum APIError: LocalizedError {
    case fixture
    var isNetworkError: Bool { false }
    var errorDescription: String? { "Disposable fixture request failed. Try again." }
}
@MainActor
enum APIClient {
    static var classes = [UserClass(_id: "physics", name: "Physics", description: "Disposable course")]
    static func delay() async throws {
        try await Task.sleep(for: .milliseconds(300))
        if ProcessInfo.processInfo.arguments.contains("--error") { throw APIError.fixture }
    }
    static func fetchNote(id: String) async throws -> NoteItem {
        try await delay()
        return NoteItem(_id: id, title: "Atomic structure", description: "Disposable study fixture",
            content: "# Structure\nProtons and neutrons form the nucleus.",
            status: ProcessInfo.processInfo.arguments.contains("--processing") ? "processing" : "completed",
            noteClass: "Physics", flashcards: [.init(front: "Negative charge?", back: "Electron"), .init(front: "Positive charge?", back: "Proton")],
            quizQuestions: [.init(question: "Which particle is negative?", wrongAnswers: ["Proton"], correctAnswer: "Electron", explanation: "Electrons are negative.", hint: "Outside the nucleus")])
    }
    static func fetchClasses() async throws -> [UserClass] { try await delay(); return classes }
    static func createClass(name: String, description: String?) async throws -> UserClass {
        try await delay()
        let item = UserClass(_id: UUID().uuidString, name: name, description: description)
        classes.append(item); return item
    }
    static func deleteClass(id: String) async throws { try await delay(); classes.removeAll { $0.id == id } }
    static func fetchProgress(id: String) async throws -> NoteProgress { try await delay(); return NoteProgress(message: "Transcribing fixture", percent: 40) }
    static func retryNote(id: String) async throws { try await delay() }
    static func updateNoteClass(id: String, noteClass: String?) async throws { try await delay() }
    static func deleteNote(id: String) async throws { try await delay() }
    static func uploadAudio(fileURL: URL, language: String, noteClass: String?) async throws -> String { try await delay(); return "fixture" }
    static func fetchTranscript(id: String) async throws -> String { try await delay(); return "Electrons have a negative charge." }
    static func chatWithNote(id: String, message: String, history: [ChatMessage]) async throws -> String { try await delay(); return "Electrons are negatively charged." }
}
