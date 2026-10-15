import SwiftUI

public struct NoteDetailView: View {
    let noteId: String

    @State private var note: NoteItem?
    @State private var progress: NoteProgress?
    @State private var isLoading: Bool
    @State private var errorMessage: String?
    @State private var isNetworkUnreachable = false
    @State private var selectedTab = 0
    @State private var isRetrying = false
    @State private var isDeleting = false
    @State private var showDeleteConfirmation = false
    @State private var showClassPicker = false
    @State private var availableClasses: [UserClass]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @State private var pollingTask: Task<Void, Never>?

    public init(noteId: String) {
        self.noteId = noteId
        let cached = LocalDataCache.shared.loadNoteDetail(id: noteId)
        _note = State(initialValue: cached)
        _isLoading = State(initialValue: cached == nil)
        let cachedClasses = LocalDataCache.shared.loadClasses() ?? []
        _availableClasses = State(initialValue: cachedClasses)
    }

    public var body: some View {
        VStack(spacing: 0) {
            if isNetworkUnreachable {
                NetworkBannerView(
                    message: "Internet is not reachable",
                    onRetry: { Task { await loadData(); startPollingIfNeeded() } }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if isLoading && note == nil {
                ProgressView("Loading note...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let errorMessage, note == nil {
                VStack(spacing: 12) {
                    Text(errorMessage).foregroundStyle(.red)
                    Button("Retry") { Task { await loadData(); startPollingIfNeeded() } }
                        .buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let note {
                if let errorMessage {
                    Text(errorMessage).font(.callout).foregroundStyle(.red).padding(.horizontal)
                }
                // Header status / processing alerts
                if note.isProcessing {
                    processingBanner
                } else if note.isError {
                    errorBanner(note: note)
                }

                // Full-width labels stay readable on small screens and at large text sizes.
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(Array(["Notes", "Flashcards", "Quiz", "Transcript", "Ask AI"].enumerated()), id: \.offset) { index, title in
                            Button {
                                withAnimation(NotebookStyle.motion(reduced: reducedMotion)) { selectedTab = index }
                            } label: {
                                Text(title)
                                    .font(.subheadline.weight(.semibold))
                                    .fixedSize()
                                    .padding(.horizontal, 16)
                                    .frame(minHeight: 44)
                                    .background(selectedTab == index ? NotebookStyle.accent : NotebookStyle.paper, in: Capsule())
                                    .foregroundStyle(selectedTab == index ? Color.white : Color.primary)
                            }
                            .buttonStyle(NotebookPressStyle())
                            .accessibilityAddTraits(selectedTab == index ? .isSelected : [])
                        }
                    }
                    .padding(.horizontal)
                }
                .padding(.vertical, 12)
                .background(NotebookStyle.canvas)

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
        .background(NotebookStyle.canvas)
        .tint(NotebookStyle.accent)
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
                .accessibilityLabel("Note actions")
                .disabled(isDeleting)
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
        .refreshable {
            await loadData()
            startPollingIfNeeded()
        }
        .task {
            await loadData()
            loadClasses()
            startPollingIfNeeded()
        }
        .onDisappear { stopPolling() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { startPollingIfNeeded() }
            else { stopPolling() }
        }
        .onChange(of: NetworkMonitor.shared.isConnected) { _, isConnected in
            if isConnected && isNetworkUnreachable {
                Task { await loadData(); startPollingIfNeeded() }
            }
        }
        .animation(NotebookStyle.motion(reduced: reducedMotion), value: isNetworkUnreachable)
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
                VStack(alignment: .leading, spacing: 12) {
                    Text(note.title)
                        .font(.title.weight(.bold))
                        .tracking(-0.5)
                        .fixedSize(horizontal: false, vertical: true)
                    ViewThatFits(in: .horizontal) {
                        noteMetadata(note)
                        VStack(alignment: .leading, spacing: 8) {
                            if let cls = note.noteClass, !cls.isEmpty { Text(cls).font(.caption.bold()).foregroundStyle(NotebookStyle.accent) }
                            if let duration = note.formattedDuration { Label(duration, systemImage: "clock").font(.caption).foregroundStyle(.secondary) }
                            if !note.formattedDate.isEmpty { Label(note.formattedDate, systemImage: "calendar").font(.caption).foregroundStyle(.secondary) }
                        }
                    }
                    if let desc = note.description, !desc.isEmpty {
                        Text(desc).font(.body).foregroundStyle(.secondary)
                    }
                }
                .padding(20)
                .notebookSurface()
                .padding(.horizontal)

                if let content = note.content, !content.isEmpty {
                    MathMarkdownView(content)
                } else if note.isProcessing {
                    Text("Note content will appear once processing finishes.")
                        .font(.subheadline).foregroundStyle(.secondary).padding()
                } else {
                    ContentUnavailableView("No Content", systemImage: "doc.text")
                }
            }
            .padding(.vertical, 20)
        }
    }

    private func noteMetadata(_ note: NoteItem) -> some View {
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

    }

    // MARK: - Actions & Polling

    @MainActor
    private func loadData() async {
            do {
                let fetched = try await APIClient.fetchNote(id: noteId)
                await MainActor.run {
                    self.note = fetched
                    self.isLoading = false
                    self.errorMessage = nil
                    LocalDataCache.shared.saveNoteDetail(fetched)
                    withAnimation(NotebookStyle.motion(reduced: reducedMotion)) {
                        self.isNetworkUnreachable = false
                    }
                }
            } catch {
                await MainActor.run {
                    self.isLoading = false
                    let isNetwork = (error as? APIError)?.isNetworkError == true || (error as? URLError) != nil || !NetworkMonitor.shared.isConnected
                    withAnimation(NotebookStyle.motion(reduced: reducedMotion)) {
                        if isNetwork {
                            self.isNetworkUnreachable = true
                        }
                    }
                    self.errorMessage = error.localizedDescription
                }
            }
    }

    private func loadClasses() {
        Task {
            if let classes = try? await APIClient.fetchClasses() {
                await MainActor.run {
                    self.availableClasses = classes
                    LocalDataCache.shared.saveClasses(classes)
                }
            }
        }
    }

    private func startPollingIfNeeded() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                guard let note, note.isProcessing else { break }

                if let prog = try? await APIClient.fetchProgress(id: noteId) {
                    await MainActor.run {
                        self.progress = prog
                    }
                }

                if let updatedNote = try? await APIClient.fetchNote(id: noteId), !Task.isCancelled {
                    await MainActor.run {
                        self.note = updatedNote
                        LocalDataCache.shared.saveNoteDetail(updatedNote)
                    }
                    if !updatedNote.isProcessing {
                        break
                    }
                }

                try? await Task.sleep(nanoseconds: 3_000_000_000)
            }
        }
    }

    private func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func retryProcessing() {
        guard !isRetrying else { return }
        isRetrying = true
        Task {
            do {
                try await APIClient.retryNote(id: noteId)
                isRetrying = false
                await loadData()
                startPollingIfNeeded()
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
                await loadData()
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
                LocalDataCache.shared.removeNote(id: noteId)
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
