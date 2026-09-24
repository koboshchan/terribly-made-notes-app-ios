import SwiftUI

public struct AskAIView: View {
    let noteId: String

    @State private var messages: [ChatMessage] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    public init(noteId: String) {
        self.noteId = noteId
    }

    public var body: some View {
        VStack(spacing: 0) {
            if messages.isEmpty && !isLoading {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "sparkles")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)

                    Text("Ask AI About This Note")
                        .font(.headline)

                    Text("Ask questions, request summaries, or clarify specific concepts.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer()
                }
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 14) {
                            ForEach(messages) { msg in
                                chatBubble(message: msg)
                            }

                            if isLoading {
                                HStack {
                                    ProgressView()
                                        .padding(.trailing, 6)
                                    Text("Thinking...")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal)
                                .id("loading_bubble")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                    .onChange(of: isLoading) { _, loading in
                        if loading {
                            withAnimation {
                                proxy.scrollTo("loading_bubble", anchor: .bottom)
                            }
                        }
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 4)
            }

            Divider()

            HStack(spacing: 10) {
                TextField("Ask a question...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .disabled(isLoading)

                Button {
                    sendMessage()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading ? Color.secondary : Color.blue)
                }
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            }
            .padding()
            .background(Color(uiColor: .systemBackground))
        }
    }

    private func chatBubble(message: ChatMessage) -> some View {
        HStack {
            if message.isUser {
                Spacer(minLength: 40)
                Text(message.content)
                    .font(.body)
                    .padding(12)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(.rect(cornerRadius: 16))
            } else {
                Text(message.content)
                    .font(.body)
                    .padding(12)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .foregroundStyle(.primary)
                    .clipShape(.rect(cornerRadius: 16))
                Spacer(minLength: 40)
            }
        }
        .id(message.id)
    }

    private func sendMessage() {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let userMessage = ChatMessage(role: "user", content: trimmed)
        messages.append(userMessage)
        inputText = ""
        isLoading = true
        errorMessage = nil

        let currentHistory = messages

        Task {
            do {
                let response = try await APIClient.chatWithNote(id: noteId, message: trimmed, history: currentHistory)
                await MainActor.run {
                    messages.append(ChatMessage(role: "assistant", content: response))
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }
}
