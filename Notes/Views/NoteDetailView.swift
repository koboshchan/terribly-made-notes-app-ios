import SwiftUI

public struct NoteDetailView: View {
    let noteId: String

    @State private var note: NoteItem?
    @State private var progress: NoteProgress?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var selectedTab = 0
    @State private var isRetrying = false
    @State private var isDeleting = false
    @State private var showDeleteConfirmation = false
    @State private var showClassPicker = false
    @State private var availableClasses: [UserClass] = []
    @Environment(\.dismiss) private var dismiss

    public init(noteId: String) {
        self.noteId = noteId
    }

    public var body: some View {
        VStack(spacing: 0) {
            if isLoading && note == nil {
                ProgressView("Loading note...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, note == nil {
                VStack(spacing: 12) {
                    Text(errorMessage).foregroundStyle(.red)
                    Button("Retry") { loadData() }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let note {
                // Header status / processing alerts
                if note.isProcessing {
                    processingBanner
                } else if note.isError {
                    errorBanner(note: note)
                }

                // Section picker
                Picker("Section", selection: $selectedTab) {
                    Text("Notes").tag(0)
                    Text("Flashcards").tag(1)
                    Text("Quiz").tag(2)
                    Text("Transcript").tag(3)
                    Text("Ask AI").tag(4)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                // Tab Content
                Group {
                    switch selectedTab {
                    case 0:
                        notesContentView(note: note)
                    case 1:
                        FlashcardsView(flashcards: note.flashcards ?? [])
                    case 2:
                        QuizView(questions: note.quizQuestions ?? [])
                    case 3:
                        TranscriptView(noteId: noteId)
                    case 4:
                        AskAIView(noteId: noteId)
                    default:
                        EmptyView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .navigationTitle(note?.title ?? "Note")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Menu {
                    if !availableClasses.isEmpty {
                        Menu("Assign Class") {
                            Button("None") { assignClass(nil) }
                            ForEach(availableClasses) { cls in
                                Button(cls.name) { assignClass(cls.name) }
                            }
                        }
                    }

                    if note?.isError == true {
                        Button {
                            retryProcessing()
                        } label: {
                            Label("Retry Processing", systemImage: "arrow.clockwise")
                        }
                    }

                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        Label("Delete Note", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
        .confirmationDialog("Delete Note?", isPresented: $showDeleteConfirmation, titleVisibility: .visible) {
            Button("Delete Note", role: .destructive) {
                deleteCurrentNote()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Are you sure you want to delete this note? This action cannot be undone.")
        }
        .task {
            loadData()
            loadClasses()
            startPollingIfNeeded()
        }
    }

    // MARK: - Subviews

    private var processingBanner: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                ProgressView()
                VStack(alignment: .leading, spacing: 2) {
                    Text(progress?.message ?? "Processing audio note...")
                        .font(.subheadline.bold())
                    if let percent = progress?.percent, percent > 0 {
                        Text("\(percent)% complete")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if let percent = progress?.percent, percent > 0 {
                ProgressView(value: Double(percent), total: 100.0)
                    .tint(.blue)
            }
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .clipShape(.rect(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func errorBanner(note: NoteItem) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                Text("Processing Failed")
                    .font(.headline)
                    .foregroundStyle(.red)
            }

            Text(note.error ?? "An error occurred while processing this note.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                retryProcessing()
            } label: {
                HStack {
                    if isRetrying {
                        ProgressView().tint(.white)
                    }
                    Text("Retry Processing")
                        .font(.subheadline.bold())
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(isRetrying)
        }
        .padding()
        .background(Color.red.opacity(0.08))
        .clipShape(.rect(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func notesContentView(note: NoteItem) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Metadata Header
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        if let cls = note.noteClass, !cls.isEmpty {
                            Text(cls)
                                .font(.caption.bold())
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.15))
                                .foregroundStyle(.blue)
                                .clipShape(.capsule)
                        }

                        if let duration = note.formattedDuration {
                            Label(duration, systemImage: "clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if !note.formattedDate.isEmpty {
                            Label(note.formattedDate, systemImage: "calendar")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    if let desc = note.description, !desc.isEmpty {
                        Text(desc)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)

                Divider()

                if let content = note.content, !content.isEmpty {
                    MathMarkdownView(content)
                } else if note.isProcessing {
                    Text("Note content will appear once processing finishes.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding()
                } else {
                    ContentUnavailableView("No Content", systemImage: "doc.text")
                }
            }
            .padding(.vertical)
        }
    }

    // MARK: - Actions & Polling

    private func loadData() {
        Task {
            do {
                let fetched = try await APIClient.fetchNote(id: noteId)
                await MainActor.run {
                    self.note = fetched
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    private func loadClasses() {
        Task {
            if let classes = try? await APIClient.fetchClasses() {
                await MainActor.run {
                    self.availableClasses = classes
                }
            }
        }
    }

    private func startPollingIfNeeded() {
        Task {
            while !Task.isCancelled {
                guard let note, note.isProcessing else { break }

                if let prog = try? await APIClient.fetchProgress(id: noteId) {
                    await MainActor.run {
                        self.progress = prog
                    }
                }

                if let updatedNote = try? await APIClient.fetchNote(id: noteId) {
                    await MainActor.run {
                        self.note = updatedNote
                    }
                    if !updatedNote.isProcessing {
                        break
                    }
                }

                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func retryProcessing() {
        isRetrying = true
        Task {
            do {
                try await APIClient.retryNote(id: noteId)
                await MainActor.run {
                    isRetrying = false
                    loadData()
                    startPollingIfNeeded()
                }
            } catch {
                await MainActor.run {
                    isRetrying = false
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func assignClass(_ cls: String?) {
        Task {
            do {
                try await APIClient.updateNoteClass(id: noteId, noteClass: cls)
                loadData()
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func deleteCurrentNote() {
        isDeleting = true
        Task {
            do {
                try await APIClient.deleteNote(id: noteId)
                await MainActor.run {
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isDeleting = false
                }
            }
        }
    }
}
