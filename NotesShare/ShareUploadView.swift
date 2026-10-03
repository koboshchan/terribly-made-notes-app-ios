import SwiftUI

public struct ShareUploadView: View {
    @State private var files: [SharedAudioFile]
    @State private var token: String?
    @State private var isProcessing = true
    @State private var allCompleted = false
    @State private var errorMessage: String?

    let onComplete: () -> Void
    let onCancel: () -> Void

    public init(
        initialFiles: [SharedAudioFile],
        onComplete: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self._files = State(initialValue: initialFiles)
        self.onComplete = onComplete
        self.onCancel = onCancel
    }

    private var completedCount: Int {
        files.filter { $0.status == .completed }.count
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                if let error = errorMessage {
                    unauthenticatedOrErrorView(message: error)
                } else if files.isEmpty && isProcessing {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(1.2)
                        Text("Reading audio files...")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    uploadingListView
                }
            }
            .padding()
            .navigationTitle("Upload to Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(allCompleted ? "Done" : "Cancel") {
                        if allCompleted {
                            onComplete()
                        } else {
                            onCancel()
                        }
                    }
                }
            }
        }
        .task {
            startUploadProcess()
        }
    }

    // MARK: - Subviews

    private var uploadingListView: some View {
        VStack(spacing: 16) {
            // Header summary
            HStack(spacing: 12) {
                Image(systemName: allCompleted ? "checkmark.circle.fill" : "waveform.circle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(allCompleted ? .green : .blue)

                VStack(alignment: .leading, spacing: 2) {
                    Text(allCompleted ? "Upload Complete!" : "Uploading \(files.count) Voice \(files.count == 1 ? "Memo" : "Memos")")
                        .font(.headline)
                    Text(allCompleted ? (files.contains { $0.status == .queued } ? "Open Notes to finish queued uploads." : "AI transcription & study notes queued.") : "Uploaded \(completedCount) of \(files.count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding()
            .background(Color(uiColor: .secondarySystemBackground))
            .clipShape(.rect(cornerRadius: 14))

            // File items
            List {
                ForEach(files) { file in
                    HStack(spacing: 12) {
                        Image(systemName: "waveform")
                            .foregroundStyle(.blue)

                        Text(file.name)
                            .font(.subheadline)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer()

                        switch file.status {
                        case .pending:
                            Image(systemName: "clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        case .uploading(let fraction):
                            if fraction > 0 {
                                ProgressView(value: fraction)
                                    .frame(width: 60)
                                    .accessibilityLabel("Uploading \(Int(fraction * 100)) percent")
                            } else {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        case .queued:
                            Label("Queued", systemImage: "tray.and.arrow.up")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        case .completed:
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .failed(let err):
                            VStack(alignment: .trailing) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.red)
                                Text(err)
                                    .font(.caption2)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func unauthenticatedOrErrorView(message: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "person.crop.circle.badge.exclamationmark")
                .font(.system(size: 54))
                .foregroundStyle(.orange)

            Text("Sign in Required")
                .font(.title3.bold())

            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()

            Button("Dismiss") {
                onCancel()
            }
            .buttonStyle(.borderedProminent)
            .padding(.bottom, 24)
        }
    }

    // MARK: - Logic

    private func startUploadProcess() {
        // Never signed in on this device: nothing we can do from here.
        guard ShareUploader.hasAnySession else {
            self.errorMessage = "Please open the Notes app and sign in first to enable automatic uploads from Voice Memos."
            self.isProcessing = false
            return
        }
        // Files are staged durably first; with an expired token they stay
        // queued and the main app sends them next time it opens.
        let token = ShareUploader.storedAuthToken()
        self.token = token

        Task {
            for i in files.indices {
                let record: UploadRecord
                do {
                    record = try ShareUploader.stage(file: files[i])
                } catch {
                    files[i].status = .failed(error.localizedDescription)
                    continue
                }

                guard let token else {
                    ShareUploader.deferToApp(record)
                    files[i].status = .queued
                    continue
                }

                files[i].status = .uploading(0)
                let progressTask = Task { @MainActor in
                    while !Task.isCancelled {
                        if let r = UploadStore.shared.record(id: record.id), r.status == .uploading {
                            files[i].status = .uploading(r.progress)
                        }
                        try? await Task.sleep(nanoseconds: 300_000_000)
                    }
                }
                do {
                    _ = try await ShareUploader.upload(record: record, token: token)
                    progressTask.cancel()
                    files[i].status = .completed
                } catch {
                    progressTask.cancel()
                    files[i].status = .failed(error.localizedDescription)
                }
            }

            self.isProcessing = false
            self.allCompleted = files.allSatisfy { $0.status == .completed || $0.status == .queued }

            if files.allSatisfy({ $0.status == .completed }) {
                // Auto-dismiss after 1.2 seconds so user sees the checkmark
                try? await Task.sleep(nanoseconds: 1_200_000_000)
                await MainActor.run {
                    onComplete()
                }
            }
        }
    }
}
