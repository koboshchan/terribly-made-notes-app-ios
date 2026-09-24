import SwiftUI
import ClerkKit
import ClerkKitUI

struct RootView: View {
    @Environment(Clerk.self) private var clerk
    @State private var authIsPresented = false

    var body: some View {
        Group {
            if clerk.user != nil {
                HomeView()
            } else {
                SignedOutView(onSignIn: { authIsPresented = true })
            }
        }
        .prefetchClerkImages()
        .sheet(isPresented: $authIsPresented) {
            AuthView()
        }
    }
}

private struct SignedOutView: View {
    let onSignIn: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "note.text")
                .font(.system(size: 72))
                .foregroundStyle(.blue)

            VStack(spacing: 8) {
                Text("Notes")
                    .font(.largeTitle.bold())

                Text("Record audio, generate AI summaries, flashcards, and study guides.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            Button(action: onSignIn) {
                Text("Sign in to Notes")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
    }
}
