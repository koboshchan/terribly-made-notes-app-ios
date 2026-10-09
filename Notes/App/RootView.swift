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
                VStack(alignment: .leading, spacing: 28) {
                    Image(systemName: "waveform")
                        .font(.system(size: 36, weight: .medium))
                        .foregroundStyle(NotebookStyle.accent)
                        .padding(24)
                        .notebookSurface()
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 12) {
                        Text("A little more\nunderstanding.")
                            .font(.largeTitle.weight(.bold))
                            .tracking(-0.8)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("Record a lesson. Return to clear notes, flashcards, and quizzes.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Button { authIsPresented = true } label: {
                        HStack {
                            Text("Sign in to Notes")
                            Spacer()
                            Image(systemName: "arrow.right")
                        }
                        .font(.headline)
                        .padding(20)
                        .foregroundStyle(.white)
                        .background(NotebookStyle.accent, in: RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(NotebookPressStyle())
                }
                .padding(28)
                .frame(maxWidth: 520, alignment: .leading)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(NotebookStyle.canvas)
            }
        }
        .sheet(isPresented: $authIsPresented) {
            AuthView()
        }
    }
}
