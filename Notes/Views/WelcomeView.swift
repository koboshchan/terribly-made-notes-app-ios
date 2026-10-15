import SwiftUI

struct WelcomeView: View {
    let onSignIn: () -> Void

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
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
                    Button(action: onSignIn) {
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
                .frame(maxWidth: .infinity)
                .frame(minHeight: geometry.size.height)
            }
            .background(NotebookStyle.canvas)
        }
    }
}
