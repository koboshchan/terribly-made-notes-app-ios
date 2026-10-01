import SwiftUI
import AVFoundation

public struct RecordNoteView: View {
    let onNoteCreated: (String) -> Void

    @State private var recorder = RecordingController()
    @State private var importedURL: URL?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var showDiscardConfirm = false
    @State private var pendingDiscardAction: DiscardAction = .rerecord
    @State private var recoverableDraft: URL?

    private enum DiscardAction { case rerecord, close }

    private var isRecording: Bool { recorder.isCapturing }
    private var isActiveSession: Bool {
        switch recorder.state {
        case .recording, .paused, .interrupted: return true
        default: return false
        }
    }
    /// The file that will be uploaded: a finished recording or an imported file.
    private var recordedURL: URL? { recorder.finishedURL ?? importedURL }
    private var recordDuration: TimeInterval { recorder.duration }

    @State private var selectedLanguage = "english"
    @State private var selectedClass = ""
    @State private var availableClasses: [UserClass] = []

    @State private var showFileImporter = false
    @State private var isUploading = false
    @State private var uploadProgressMessage = ""
    @State private var errorMessage: String?

    @Environment(\.dismiss) private var dismiss

    public init(onNoteCreated: @escaping (String) -> Void) {
        self.onNoteCreated = onNoteCreated
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    // Recording Card
                    VStack(spacing: 20) {
                        ZStack {
                            Circle()
                                .fill(isRecording ? Color.red.opacity(0.15) : Color.blue.opacity(0.1))
                                .frame(width: 140, height: 140)
                                .scaleEffect(isRecording ? 1.1 : 1.0)
                                .animation(isRecording ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true) : .default, value: isRecording)

                            Image(systemName: isRecording ? "waveform" : "mic.fill")
                                .font(.system(size: 48))
                                .foregroundStyle(isRecording ? .red : .blue)
                        }
                        .padding(.top, 12)

                        Text(formattedTime(recordDuration))
                            .font(.system(size: 40, weight: .semibold, design: .monospaced))

                        if recorder.state == .interrupted || recorder.state == .paused {
                            Text(recorder.state == .interrupted ? "Paused by the system" : "Paused")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)
                        }

                        HStack(spacing: 16) {
                            if !isActiveSession && recordedURL == nil {
                                Button {
                                    recorder.start()
                                } label: {
                                    Label("Start Recording", systemImage: "circle.fill")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 14)
                                        .background(Color.red)
                                        .clipShape(.capsule)
                                }
                            } else if isActiveSession {
                                Button {
                                    if isRecording { recorder.pause() } else { recorder.resume() }
                                } label: {
                                    Label(isRecording ? "Pause" : "Resume", systemImage: isRecording ? "pause.fill" : "record.circle")
                                        .font(.headline)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 6)
                                }
                                .buttonStyle(.bordered)

                                Button {
                                    recorder.stop()
                                } label: {
                                    Label("Stop", systemImage: "stop.fill")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 14)
                                        .background(Color.black)
                                        .clipShape(.capsule)
                                }
                            } else if let recordedURL {
                                // Recorded preview controls
                                Button {
                                    togglePlayback(url: recordedURL)
                                } label: {
                                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                                        .font(.system(size: 44))
                                        .foregroundStyle(.blue)
                                }
                                .accessibilityLabel(isPlaying ? "Pause preview" : "Play preview")

                                Button {
                                    requestDiscard(.rerecord)
                                } label: {
                                    Label("Re-record", systemImage: "arrow.counterclockwise")
                                        .font(.subheadline)
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        // Or choose a file button
                        if let draft = recoverableDraft, !isActiveSession, recordedURL == nil {
                            Button {
                                recorder.restore(draft: draft)
                                recoverableDraft = nil
                            } label: {
                                Label("Recover unsaved recording", systemImage: "arrow.uturn.backward.circle")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.orange)
                        }

                        if !isActiveSession && recordedURL == nil {
                            Button {
                                showFileImporter = true
                            } label: {
                                Label("Import Audio File", systemImage: "folder")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.bordered)
                        } else if let recordedURL, !isActiveSession {
                            Text("Ready to upload: \(recordedURL.lastPathComponent)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(24)
                    .frame(maxWidth: .infinity)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 16))
                    .padding(.horizontal)

                    // Options Card
                    VStack(alignment: .leading, spacing: 16) {
                        Text("OPTIONS")
                            .font(.caption2.bold())
                            .foregroundStyle(.secondary)

                        // Language picker
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Language")
                                .font(.subheadline.bold())
                            Picker("Language", selection: $selectedLanguage) {
                                Text("English").tag("english")
                                Text("Other Language").tag("other")
                            }
                            .pickerStyle(.segmented)
                        }

                        // Class picker
                        if !availableClasses.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Class / Subject (Optional)")
                                    .font(.subheadline.bold())
                                Picker("Class", selection: $selectedClass) {
                                    Text("None").tag("")
                                    ForEach(availableClasses) { cls in
                                        Text(cls.name).tag(cls.name)
                                    }
                                }
                                .pickerStyle(.menu)
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(uiColor: .secondarySystemBackground))
                    .clipShape(.rect(cornerRadius: 16))
                    .padding(.horizontal)

                    if let errorMessage = errorMessage ?? recorder.errorMessage {
                        Text(errorMessage)
                            .font(.subheadline)
                            .foregroundStyle(.red)
                            .padding(.horizontal)
                    }

                    // Upload Button
                    if let fileToUpload = recordedURL {
                        Button {
                            uploadNote(url: fileToUpload)
                        } label: {
                            HStack {
                                if isUploading {
                                    ProgressView().tint(.white).padding(.trailing, 6)
                                    Text(uploadProgressMessage.isEmpty ? "Uploading..." : uploadProgressMessage)
                                } else {
                                    Label("Process Note", systemImage: "sparkles")
                                }
                            }
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.horizontal)
                        .disabled(isUploading)
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("New Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        if recorder.hasUnsavedAudio {
                            requestDiscard(.close)
                        } else {
                            dismiss()
                        }
                    }
                    .disabled(isUploading)
                }
            }
            .confirmationDialog(
                "Discard this recording?",
                isPresented: $showDiscardConfirm,
                titleVisibility: .visible
            ) {
                Button("Discard Recording", role: .destructive) {
                    stopPlayback()
                    recorder.discard()
                    importedURL = nil
                    if pendingDiscardAction == .close { dismiss() }
                }
                if pendingDiscardAction == .close {
                    Button("Keep as Draft") {
                        // The file stays in Drafts and is offered for recovery next time.
                        recorder.stop()
                        dismiss()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This audio hasn't been uploaded yet.")
            }
            .interactiveDismissDisabled(recorder.hasUnsavedAudio || isUploading)
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let first = urls.first {
                        importedURL = first
                    }
                case .failure(let error):
                    errorMessage = error.localizedDescription
                }
            }
            .task {
                if let classes = try? await APIClient.fetchClasses() {
                    availableClasses = classes
                }
            }
            .onAppear {
                if case .idle = recorder.state, importedURL == nil {
                    recoverableDraft = RecordingController.recoverableDraft()
                }
            }
            .onDisappear {
                // Stopping (not discarding) keeps the draft file on disk.
                recorder.tearDown()
                stopPlayback()
            }
        }
    }

    // MARK: - Audio Recording Helpers

    private func requestDiscard(_ action: DiscardAction) {
        guard recorder.hasUnsavedAudio else {
            // Only an imported file is selected. It isn't ours to delete,
            // so just clear the selection.
            stopPlayback()
            importedURL = nil
            if action == .close { dismiss() }
            return
        }
        pendingDiscardAction = action
        showDiscardConfirm = true
    }

    private func stopPlayback() {
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
    }

    private func togglePlayback(url: URL) {
        if isPlaying {
            audioPlayer?.stop()
            isPlaying = false
            return
        }

        let didStart = url.startAccessingSecurityScopedResource()
        defer {
            if didStart { url.stopAccessingSecurityScopedResource() }
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback)
            try AVAudioSession.sharedInstance().setActive(true)
            audioPlayer = try AVAudioPlayer(contentsOf: url)
            audioPlayer?.play()
            isPlaying = true
        } catch {
            errorMessage = "Failed to play audio: \(error.localizedDescription)"
        }
    }

    private func formattedTime(_ duration: TimeInterval) -> String {
        let minutes = Int(duration) / 60
        let seconds = Int(duration) % 60
        return String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Upload

    private func uploadNote(url: URL) {
        isUploading = true
        uploadProgressMessage = "Uploading audio..."
        errorMessage = nil

        Task {
            do {
                let noteId = try await APIClient.uploadAudio(
                    fileURL: url,
                    language: selectedLanguage,
                    noteClass: selectedClass.isEmpty ? nil : selectedClass
                )
                await MainActor.run {
                    isUploading = false
                    stopPlayback()
                    // The upload was staged as its own copy, so the draft can go.
                    recorder.uploadSucceeded()
                    importedURL = nil
                    onNoteCreated(noteId)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isUploading = false
                    errorMessage = error.localizedDescription
                }
            }
        }
    }
}
