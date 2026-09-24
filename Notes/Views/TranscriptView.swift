import SwiftUI

public struct TranscriptView: View {
    let noteId: String

    @State private var transcript: String?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showCopiedAlert = false

    public init(noteId: String) {
        self.noteId = noteId
    }

    public var body: some View {
        VStack {
            if isLoading {
                ProgressView("Loading transcript...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage {
                VStack(spacing: 12) {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                    Button("Retry") {
                        loadTranscript()
                    }
                    .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let transcript, !transcript.isEmpty {
                ScrollView {
                    Text(transcript)
                        .font(.body)
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            UIPasteboard.general.string = transcript
                            showCopiedAlert = true
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
                }
                .alert("Copied to Clipboard", isPresented: $showCopiedAlert) {
                    Button("OK", role: .cancel) { }
                }
            } else {
                ContentUnavailableView(
                    "No Transcript Available",
                    systemImage: "waveform.slash",
                    description: Text("Transcript for this audio is not available.")
                )
            }
        }
        .task {
            loadTranscript()
        }
    }

    private func loadTranscript() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let text = try await APIClient.fetchTranscript(id: noteId)
                await MainActor.run {
                    transcript = text
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
