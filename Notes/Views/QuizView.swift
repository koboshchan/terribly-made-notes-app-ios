import SwiftUI

public struct QuizView: View {
    let questions: [QuizQuestion]

    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @State private var currentQuestionIndex = 0
    @State private var selectedOption: String?
    @State private var hasSubmitted = false
    @State private var score = 0
    @State private var showHint = false
    @State private var optionsForCurrentQuestion: [String] = []

    public init(questions: [QuizQuestion]) {
        self.questions = questions
        _optionsForCurrentQuestion = State(initialValue: questions.first?.allOptions ?? [])
    }

    public var body: some View {
        VStack(spacing: 20) {
            if questions.isEmpty {
                ContentUnavailableView(
                    "No Quiz Questions",
                    systemImage: "questionmark.circle",
                    description: Text("No quiz questions were generated for this note.")
                )
            } else if currentQuestionIndex >= questions.count {
                // Completed state
                VStack(spacing: 16) {
                    Spacer()

                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.green)

                    Text("Quiz Completed!")
                        .font(.title2.bold())

                    Text("You scored \(score) out of \(questions.count)")
                        .font(.headline)
                        .foregroundStyle(.secondary)

                    Button("Restart Quiz") {
                        restartQuiz()
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 16)

                    Spacer()
                }
            } else {
                let question = questions[currentQuestionIndex]

                // Progress & Score Header
                HStack {
                    Text("Question \(currentQuestionIndex + 1) of \(questions.count)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Spacer()

                    Text("Score: \(score)")
                        .font(.subheadline.bold())
                        .foregroundStyle(.primary)
                }
                .padding(.horizontal)

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        Text(question.question)
                            .font(.title3.bold())
                            .padding(.horizontal)

                        if let hint = question.hint, !hint.isEmpty {
                            DisclosureGroup(isExpanded: $showHint) {
                                Text(hint)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .padding(.top, 4)
                            } label: {
                                Label("Need a hint?", systemImage: "lightbulb.fill")
                                    .font(.caption.bold())
                                    .foregroundStyle(.orange)
                            }
                            .padding(.horizontal)
                        }

                        // Choices
                        VStack(spacing: 12) {
                            ForEach(optionsForCurrentQuestion, id: \.self) { option in
                                choiceButton(option: option, question: question)
                            }
                        }
                        .padding(.horizontal)

                        // Explanation after answering
                        if hasSubmitted, let explanation = question.explanation, !explanation.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("EXPLANATION")
                                    .font(.caption2.bold())
                                    .foregroundStyle(.secondary)
                                Text(explanation)
                                    .font(.subheadline)
                            }
                            .padding()
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(NotebookStyle.paper)
                            .clipShape(.rect(cornerRadius: 12))
                            .padding(.horizontal)
                        }
                    }
                    .padding(.vertical)
                }

                if !hasSubmitted {
                    Button("Check Answer") { submitAnswer() }
                        .buttonStyle(.borderedProminent)
                        .disabled(selectedOption == nil)
                        .padding(.bottom, 8)
                }

                // Next Button
                if hasSubmitted {
                    Button {
                        advanceToNextQuestion()
                    } label: {
                        Text(currentQuestionIndex + 1 < questions.count ? "Next Question" : "See Results")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
                }
            }
        }
        .onChange(of: questions) { _, _ in restartQuiz() }
    }

    private func choiceButton(option: String, question: QuizQuestion) -> some View {
        let isSelected = selectedOption == option
        let isCorrect = option == question.correctAnswer

        var backgroundColor: Color = NotebookStyle.paper
        var borderColor: Color = .clear
        var textColor: Color = .primary

        if hasSubmitted {
            if isCorrect {
                backgroundColor = Color.green.opacity(0.15)
                borderColor = Color.green
                textColor = .green
            } else if isSelected {
                backgroundColor = Color.red.opacity(0.15)
                borderColor = Color.red
                textColor = .red
            }
        } else if isSelected {
            backgroundColor = Color.blue.opacity(0.15)
            borderColor = Color.blue
        }

        return Button {
            guard !hasSubmitted else { return }
            withAnimation(NotebookStyle.motion(reduced: reducedMotion)) { selectedOption = option }

        } label: {
            HStack {
                Text(option)
                    .font(.body)
                    .foregroundStyle(textColor)
                    .multilineTextAlignment(.leading)

                Spacer()

                if hasSubmitted {
                    if isCorrect {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    } else if isSelected {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(backgroundColor)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(borderColor, lineWidth: 2)
            )
            .clipShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(NotebookPressStyle())
        .disabled(hasSubmitted)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(hasSubmitted ? (isCorrect ? "Correct answer" : (isSelected ? "Your answer, incorrect" : "")) : "")
    }

    private func submitAnswer() {
        guard !hasSubmitted, let selectedOption, currentQuestionIndex < questions.count else { return }
        hasSubmitted = true
        if selectedOption == questions[currentQuestionIndex].correctAnswer { score += 1 }
    }

    private func setupQuestion() {
        guard currentQuestionIndex < questions.count else { return }
        selectedOption = nil
        hasSubmitted = false
        showHint = false
        optionsForCurrentQuestion = questions[currentQuestionIndex].allOptions
    }

    private func advanceToNextQuestion() {
        currentQuestionIndex += 1
        setupQuestion()
    }

    private func restartQuiz() {
        currentQuestionIndex = 0
        score = 0
        setupQuestion()
    }
}
