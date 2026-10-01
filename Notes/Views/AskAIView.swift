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
                        VStack(spacing: 14) {
                            ForEach(messages) { msg in
                                chatBubble(message: msg)
                            }

                            if isLoading {
                                HStack(spacing: 8) {
                                    ProgressView()
                                        .controlSize(.small)
                                    Text("AI is thinking...")
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .id("loading_bubble")
                            }
                        }
                        .padding()
                    }
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            withAnimation(.easeOut(duration: 0.25)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                            Task {
                                try? await Task.sleep(nanoseconds: 200_000_000)
                                await MainActor.run {
                                    withAnimation(.easeOut(duration: 0.2)) {
                                        proxy.scrollTo(last.id, anchor: .bottom)
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: isLoading) { _, loading in
                        if loading {
                            withAnimation(.easeOut(duration: 0.25)) {
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
                .accessibilityLabel("Send message")
                .disabled(inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            }
            .padding()
            .background(Color(uiColor: .systemBackground))
        }
    }

    private func chatBubble(message: ChatMessage) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            if message.isUser {
                Spacer(minLength: 40)
                Text(LocalizedStringKey(message.content))
                    .font(.body)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .foregroundStyle(.white)
                    .clipShape(.rect(cornerRadius: 16))
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = message.content
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
            } else {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.blue)
                        .frame(width: 26, height: 26)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(Circle())
                        .padding(.top, 4)

                    VStack(alignment: .leading, spacing: 0) {
                        MathMarkdownView(
                            message.content,
                            fontSize: 15,
                            customPadding: "0",
                            allowsInteraction: true,
                            showLoadingPlaceholder: false,
                            initialHeight: 40
                        )
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 16))
                    .contextMenu {
                        Button {
                            UIPasteboard.general.string = message.content
                        } label: {
                            Label("Copy Markdown", systemImage: "doc.on.doc")
                        }
                    }
                }
                Spacer(minLength: 20)
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
