import SwiftUI

public struct FlashcardsView: View {
    let flashcards: [Flashcard]

    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @State private var currentIndex = 0
    @State private var isFlipped = false
    @State private var cards: [Flashcard] = []

    public init(flashcards: [Flashcard]) {
        self.flashcards = flashcards
        _cards = State(initialValue: flashcards)
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
                        withAnimation(NotebookStyle.motion(reduced: reducedMotion)) {
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

                FlipCardView(isFlipped: isFlipped) {
                    cardFace(
                        title: "QUESTION",
                        titleColor: .blue,
                        content: card.front
                    )
                } back: {
                    cardFace(
                        title: "ANSWER",
                        titleColor: .green,
                        content: card.back
                    )
                }
                .id(currentIndex)
                .padding(.horizontal)
                .contentShape(Rectangle())
                .onTapGesture {
                    withAnimation(NotebookStyle.motion(reduced: reducedMotion)) {
                        isFlipped.toggle()
                    }
                }

                // Navigation controls
                HStack(spacing: 40) {
                    Button {
                        if currentIndex > 0 {
                            withAnimation(NotebookStyle.motion(reduced: reducedMotion)) {
                                currentIndex -= 1
                                isFlipped = false
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.left.circle.fill")
                            .font(.system(size: 44))
                    }
                    .accessibilityLabel("Previous card")
                    .disabled(currentIndex == 0)

                    Button {
                        withAnimation(NotebookStyle.motion(reduced: reducedMotion)) {
                            isFlipped.toggle()
                        }
                    } label: {
                        Text(isFlipped ? "Question" : "Answer")
                            .font(.headline)
                            .frame(minWidth: 80, minHeight: 44)
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        if currentIndex < cards.count - 1 {
                            withAnimation(NotebookStyle.motion(reduced: reducedMotion)) {
                                currentIndex += 1
                                isFlipped = false
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 44))
                    }
                    .accessibilityLabel("Next card")
                    .disabled(currentIndex == cards.count - 1)
                }
                .padding(.top, 8)

                Spacer()
            }
        }
        .padding(.vertical)
        .onChange(of: flashcards) { _, newCards in
            cards = newCards
            currentIndex = 0
            isFlipped = false
        }
    }

    @ViewBuilder
    private func cardFace(title: String, titleColor: Color, content: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: NotebookStyle.corner)
                .fill(NotebookStyle.paper)
                .shadow(color: .black.opacity(0.08), radius: 8, x: 0, y: 4)

            VStack(spacing: 12) {
                Text(title)
                    .font(.caption.bold())
                    .foregroundStyle(titleColor)
                    .tracking(1.5)

                ScrollView {
                    VStack {
                        Spacer(minLength: 0)

                        MathMarkdownView(
                            content,
                            isCentered: true,
                            fontSize: 19,
                            allowsInteraction: false,
                            showLoadingPlaceholder: false,
                            initialHeight: 80
                        )
                        .padding(.horizontal, 8)

                        Spacer(minLength: 0)
                    }
                    .frame(minHeight: 180)
                }

                Text("Tap to flip")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: 320, maxHeight: 440)
    }
}

// MARK: - 3D Flip Card Container

private struct FlipCardView<Front: View, Back: View>: View {
    let isFlipped: Bool
    @ViewBuilder let front: () -> Front
    @ViewBuilder let back: () -> Back

    @Environment(\.accessibilityReduceMotion) private var reducedMotion

    var body: some View {
        ZStack {
            front()
                .rotation3DEffect(
                    .degrees(reducedMotion ? 0 : (isFlipped ? 180 : 0)),
                    axis: (x: 0.0, y: 1.0, z: 0.0),
                    perspective: 0.5
                )
                .opacity(isFlipped ? 0 : 1)
                .allowsHitTesting(!isFlipped)
                .accessibilityHidden(isFlipped)

            back()
                .rotation3DEffect(
                    .degrees(reducedMotion ? 0 : (isFlipped ? 0 : -180)),
                    axis: (x: 0.0, y: 1.0, z: 0.0),
                    perspective: 0.5
                )
                .opacity(isFlipped ? 1 : 0)
                .allowsHitTesting(isFlipped)
                .accessibilityHidden(!isFlipped)
        }
    }
}
