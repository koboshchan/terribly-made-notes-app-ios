import SwiftUI

public struct TranscriptView: View {
    let noteId: String

    @State private var transcript: String?
    @State private var isLoading: Bool
    @State private var isShowingCachedCopy = false
    @State private var errorMessage: String?
    @State private var showCopiedAlert = false
    @State private var showEditor = false

    public init(noteId: String) {
        self.noteId = noteId
        let cached = LocalDataCache.shared.loadTranscript(id: noteId)
        _transcript = State(initialValue: cached)
        _isLoading = State(initialValue: cached == nil)
    }

    public var body: some View {
        VStack {
            if isLoading && transcript == nil {
                ProgressView("Loading transcript...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, transcript == nil {
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
                    if isShowingCachedCopy {
                        Label("Offline copy", systemImage: "icloud.slash")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal)
                    }
                    Text(transcript)
                        .font(.body)
                        .lineSpacing(6)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showEditor = true
                        } label: {
                            Label("Correct Transcript", systemImage: "pencil")
                        }
                        .disabled(isShowingCachedCopy)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            UIPasteboard.general.string = transcript
                            showCopiedAlert = true
                        } label: {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
                }
                .sheet(isPresented: $showEditor) {
                    TextCorrectionView(
                        title: "Correct Transcript",
                        showsTitleField: false,
                        editedTitle: "",
                        text: transcript
                    ) { _, corrected in
                        try await APIClient.updateTranscript(id: noteId, transcript: corrected)
                        self.transcript = corrected
                        LocalDataCache.shared.saveTranscript(corrected, id: noteId)
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
        isLoading = transcript == nil
        errorMessage = nil
        Task {
            do {
                let text = try await APIClient.fetchTranscript(id: noteId)
                await MainActor.run {
                    transcript = text
                    isShowingCachedCopy = false
                    isLoading = false
                    if !text.isEmpty { LocalDataCache.shared.saveTranscript(text, id: noteId) }
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    // Keep showing the cached copy when offline.
                    isShowingCachedCopy = transcript != nil
                    isLoading = false
                }
            }
        }
    }
}
