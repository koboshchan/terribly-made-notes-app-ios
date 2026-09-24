import SwiftUI
import AVFoundation

public struct RecordNoteView: View {
    let onNoteCreated: (String) -> Void

    @State private var isRecording = false
    @State private var recordedURL: URL?
    @State private var audioRecorder: AVAudioRecorder?
    @State private var audioPlayer: AVAudioPlayer?
    @State private var isPlaying = false
    @State private var recordDuration: TimeInterval = 0
    @State private var timer: Timer?

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

                        HStack(spacing: 24) {
                            if !isRecording && recordedURL == nil {
                                Button {
                                    startRecording()
                                } label: {
                                    Label("Start Recording", systemImage: "circle.fill")
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 24)
                                        .padding(.vertical, 14)
                                        .background(Color.red)
                                        .clipShape(.capsule)
                                }
                            } else if isRecording {
                                Button {
                                    stopRecording()
                                } label: {
                                    Label("Stop Recording", systemImage: "stop.fill")
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

                                Button {
                                    resetRecording()
                                } label: {
                                    Label("Re-record", systemImage: "arrow.counterclockwise")
                                        .font(.subheadline)
                                }
                                .buttonStyle(.bordered)
                            }
                        }

                        // Or choose a file button
                        if !isRecording && recordedURL == nil {
                            Button {
                                showFileImporter = true
                            } label: {
                                Label("Import Audio File", systemImage: "folder")
                                    .font(.subheadline)
                            }
                            .buttonStyle(.bordered)
                        } else if let recordedURL, !isRecording {
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

                    if let errorMessage {
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
                        stopRecording()
                        dismiss()
                    }
                    .disabled(isUploading)
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.audio],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let first = urls.first {
                        recordedURL = first
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
        }
    }

    // MARK: - Audio Recording Helpers

    private func startRecording() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try session.setActive(true)
        } catch {
            errorMessage = "Audio session setup failed: \(error.localizedDescription)"
            return
        }

        session.requestRecordPermission { allowed in
            DispatchQueue.main.async {
                if allowed {
                    beginRecording()
                } else {
                    errorMessage = "Microphone access denied. Please enable in Settings."
                }
            }
        }
    }

    private func beginRecording() {
        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("note_recording_\(Date().timeIntervalSince1970).m4a")

        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 44100.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.record()
            recordedURL = fileURL
            isRecording = true
            recordDuration = 0
            errorMessage = nil

            timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
                recordDuration += 1
            }
        } catch {
            errorMessage = "Failed to start recording: \(error.localizedDescription)"
        }
    }

    private func stopRecording() {
        audioRecorder?.stop()
        audioRecorder = nil
        timer?.invalidate()
        timer = nil
        isRecording = false
    }

    private func resetRecording() {
        stopRecording()
        audioPlayer?.stop()
        audioPlayer = nil
        isPlaying = false
        recordDuration = 0
        recordedURL = nil
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
