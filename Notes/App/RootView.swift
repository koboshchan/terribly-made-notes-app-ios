import SwiftUI
import ClerkKit
import ClerkKitUI

struct RootView: View {
    @Environment(Clerk.self) private var clerk
    @State private var authIsPresented = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if let user = clerk.user {
                // Scope the cache before HomeView reads it in init.
                let _ = LocalDataCache.shared.setScope(userId: user.id)
                HomeView()
                    .id(user.id)
            } else {
                VStack(spacing: 16) {
                    Text("Notes")
                        .font(.largeTitle.bold())
                    Text("Record audio. Get summaries, flashcards, and quizzes.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Button("Sign in") { authIsPresented = true }
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .sheet(isPresented: $authIsPresented) {
            AuthView()
        }
        .onChange(of: scenePhase) { _, phase in
            // Keep the extension's copy of the session token fresh.
            if phase == .active, clerk.user != nil {
                Task {
                    _ = try? await APIClient.currentToken()
                    await APIClient.resumeQueuedUploads()
                }
            }
        }
        .onChange(of: clerk.user?.id, initial: true) { oldId, newId in
            // Signed out, or switched accounts: drop everything the previous
            // session left on disk.
            if newId == nil || (oldId != nil && oldId != newId) {
                Task { @MainActor in
                    await SessionCleanup.signedOut()
                    if let newId { LocalDataCache.shared.setScope(userId: newId) }
                }
            }
        }
    }
}
