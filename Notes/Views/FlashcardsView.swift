import SwiftUI

public struct FlashcardsView: View {
    let flashcards: [Flashcard]

    @State private var currentIndex = 0
    @State private var isFlipped = false
    @State private var cards: [Flashcard] = []

    public init(flashcards: [Flashcard]) {
        self.flashcards = flashcards
    }

    public var body: some View {
        VStack(spacing: 20) {
            if cards.isEmpty {
                ContentUnavailableView(
                    "No Flashcards",
                    systemImage: "rectangle.portrait.on.rectangle.portrait.angled",
                    description: Text("No flashcards were generated for this note.")
                )
            } else {
                HStack {
                    Text("Card \(currentIndex + 1) of \(cards.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button {
                        withAnimation {
                            cards.shuffle()
                            currentIndex = 0
                            isFlipped = false
                        }
                    } label: {
                        Label("Shuffle", systemImage: "shuffle")
                            .font(.caption)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.horizontal)

                // Flashcard presentation
                let card = cards[currentIndex]

                ZStack {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(uiColor: .secondarySystemBackground))
                        .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)

                    VStack(spacing: 16) {
                        Text(isFlipped ? "ANSWER" : "QUESTION")
                            .font(.caption.bold())
                            .foregroundStyle(isFlipped ? .green : .blue)
                            .tracking(1.5)

                        ScrollView {
                            Text(isFlipped ? card.back : card.front)
                                .font(.title3)
                                .fontWeight(.medium)
                                .multilineTextAlignment(.center)
                                .padding()
                        }

                        Text("Tap to flip")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(24)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 320)
                .padding(.horizontal)
                .rotation3DEffect(
                    .degrees(isFlipped ? 180 : 0),
                    axis: (x: 0.0, y: 1.0, z: 0.0)
                )
                .onTapGesture {
                    withAnimation(.spring(duration: 0.4)) {
                        isFlipped.toggle()
                    }
                }

                // Navigation controls
                HStack(spacing: 40) {
                    Button {
                        if currentIndex > 0 {
                            withAnimation {
                                currentIndex -= 1
                                isFlipped = false
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.left.circle.fill")
                            .font(.system(size: 44))
                    }
                    .disabled(currentIndex == 0)

                    Button {
                        withAnimation(.spring(duration: 0.4)) {
                            isFlipped.toggle()
                        }
                    } label: {
                        Text("Flip")
                            .font(.headline)
                            .frame(width: 80)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        if currentIndex < cards.count - 1 {
                            withAnimation {
                                currentIndex += 1
                                isFlipped = false
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 44))
                    }
                    .disabled(currentIndex == cards.count - 1)
                }
                .padding(.top, 8)

                Spacer()
            }
        }
        .padding(.vertical)
        .onAppear {
            cards = flashcards
        }
    }
}
