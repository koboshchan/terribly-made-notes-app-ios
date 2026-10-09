import SwiftUI
import ClerkKitUI

public struct HomeView: View {
    @State private var notes: [NoteItem]
    @State private var classes: [UserClass]
    @State private var selectedClassFilter: String = "All"
    @State private var searchText = ""
    @State private var isLoading: Bool
    @State private var errorMessage: String?
    @State private var isNetworkUnreachable = false
    @State private var showRecordSheet = false
    @State private var showClassesSheet = false
    @State private var retryingNoteIds: Set<String> = []
    @State private var noteToAssignClass: NoteItem?
    @State private var showAssignClassDialog = false
    @State private var noteToDelete: NoteItem?
    @State private var pollingTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    public init() {
        let cachedNotes = LocalDataCache.shared.loadNotes() ?? []
        let cachedClasses = LocalDataCache.shared.loadClasses() ?? []
        _notes = State(initialValue: cachedNotes)
        _classes = State(initialValue: cachedClasses)
        _isLoading = State(initialValue: cachedNotes.isEmpty)
    }

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if isNetworkUnreachable {
                    NetworkBannerView(
                        message: "Internet is not reachable",
                        onRetry: {
                            Task {
                                await refreshAllData()
                            }
                        }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                List {
                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }

                    if isLoading && notes.isEmpty {
                        ProgressView("Loading notes…")
                            .frame(maxWidth: .infinity)
                    } else if filteredNotes.isEmpty && errorMessage == nil {
                        ContentUnavailableView {
                            Label(hasActiveFilters ? "No Matching Notes" : "Your Notebook Is Empty",
                                  systemImage: hasActiveFilters ? "magnifyingglass" : "note.text")
                        } description: {
                            Text(hasActiveFilters ? "Try another search or show all classes." : "Record a lesson or import audio to get started.")
                        } actions: {
                            if hasActiveFilters {
                                Button("Clear Filters") {
                                    searchText = ""
                                    selectedClassFilter = "All"
                                }
                            } else {
                                Button("Create a Note") { showRecordSheet = true }
                                    .buttonStyle(.borderedProminent)
                            }
                        }
                    }

                    ForEach(filteredNotes) { note in
                        NavigationLink(value: note.id) {
                            noteRow(note: note)
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                noteToDelete = note
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }

                            if !classes.isEmpty {
                                Button {
                                    noteToAssignClass = note
                                    showAssignClassDialog = true
                                } label: {
                                    Label("Class", systemImage: "folder")
                                }
                                .tint(.blue)
                            }

                            if note.isError {
                                Button {
                                    retryNote(note)
                                } label: {
                                    Label("Retry", systemImage: "arrow.clockwise")
                                }
                                .tint(.green)
                                .disabled(retryingNoteIds.contains(note.id))
                            }
                        }
                    }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: isNetworkUnreachable)
            .navigationDestination(for: String.self) { noteId in
                NoteDetailView(noteId: noteId)
            }
            .navigationTitle("Notes")
            .searchable(text: $searchText, prompt: "Search notes...")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    UserButton()
                }

                ToolbarItemGroup(placement: .topBarTrailing) {
                    // Filter Menu
                    Menu {
                        Section("Filter by Class") {
                            Button {
                                selectedClassFilter = "All"
                            } label: {
                                HStack {
                                    Text("All Notes")
                                    if selectedClassFilter == "All" {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }

                            ForEach(classes) { cls in
                                Button {
                                    selectedClassFilter = cls.name
                                } label: {
                                    HStack {
                                        Text(cls.name)
                                        if selectedClassFilter == cls.name {
                                            Image(systemName: "checkmark")
                                        }
                                    }
                                }
                            }
                        }
                    } label: {
                        Image(systemName: selectedClassFilter == "All" ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .accessibilityLabel("Filter by class")
                    .accessibilityValue(selectedClassFilter)

                    // Classes Manager
                    Button {
                        showClassesSheet = true
                    } label: {
                        Image(systemName: "folder")
                    }
                    .accessibilityLabel("Manage classes")

                    // Record Note
                    Button {
                        showRecordSheet = true
                    } label: {
                        Image(systemName: "mic.badge.plus")
                    }
                    .accessibilityLabel("Record or import a note")
                }
            }
            .sheet(isPresented: $showRecordSheet) {
                RecordNoteView { _ in
                    Task {
                        await refreshAllData()
                    }
                }
            }
            .sheet(isPresented: $showClassesSheet, onDismiss: {
                Task { await refreshAllData() }
            }) {
                ClassesView()
            }
            .confirmationDialog("Delete Note?", isPresented: Binding(
                get: { noteToDelete != nil },
                set: { if !$0 { noteToDelete = nil } }
            ), titleVisibility: .visible, presenting: noteToDelete) { note in
                Button("Delete Note", role: .destructive) { deleteNote(note) }
                Button("Cancel", role: .cancel) { noteToDelete = nil }
            } message: { note in
                Text("“\(note.title)” will be permanently deleted. This cannot be undone.")
            }
            .confirmationDialog(
                "Assign Class",
                isPresented: $showAssignClassDialog,
                titleVisibility: .visible,
                presenting: noteToAssignClass
            ) { note in
                Button("None (Remove Class)") {
                    assignClass(note: note, className: nil)
                }
                ForEach(classes) { cls in
                    Button(cls.name) {
                        assignClass(note: note, className: cls.name)
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .refreshable {
                await refreshAllData()
            }
            .task {
                await refreshAllData()
                startBackgroundPolling()
            }
            .onDisappear { stopBackgroundPolling() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { startBackgroundPolling() }
                else { stopBackgroundPolling() }
            }
            .onChange(of: NetworkMonitor.shared.isConnected) { _, isConnected in
                if isConnected && isNetworkUnreachable {
                    Task {
                        await refreshAllData()
                    }
                }
            }
        }
    }

    // MARK: - Row Subview

    private func noteRow(note: NoteItem) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(note.title)
                    .font(.headline)
                    .lineLimit(2)

                Spacer()

                statusBadge(note: note)
            }

            if let desc = note.description, !desc.isEmpty {
                Text(desc)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                if let cls = note.noteClass, !cls.isEmpty {
                    Text(cls)
                        .font(.caption2.bold())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12))
                        .foregroundStyle(.blue)
                        .clipShape(.capsule)
                }

                if let duration = note.formattedDuration {
                    Label(duration, systemImage: "clock")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                if !note.formattedDate.isEmpty {
                    Label(note.formattedDate, systemImage: "calendar")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if note.isError {
                    Button {
                        retryNote(note)
                    } label: {
                        HStack(spacing: 4) {
                            if retryingNoteIds.contains(note.id) {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Image(systemName: "arrow.clockwise")
                            }
                            Text("Retry")
                        }
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.green)
                        .clipShape(.capsule)
                    }
                    .buttonStyle(.plain)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(Rectangle())
                    .disabled(retryingNoteIds.contains(note.id))
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func statusBadge(note: NoteItem) -> some View {
        Group {
            if note.isProcessing {
                HStack(spacing: 4) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Processing")
                        .font(.caption2.bold())
                        .foregroundStyle(.blue)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.1))
                .clipShape(.capsule)
            } else if note.isError {
                Text("Failed")
                    .font(.caption2.bold())
                    .foregroundStyle(.red)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.red.opacity(0.1))
                    .clipShape(.capsule)
            }
        }
    }

    // MARK: - Computed

    private var hasActiveFilters: Bool {
        !searchText.isEmpty || selectedClassFilter != "All"
    }

    private var filteredNotes: [NoteItem] {
        notes.filter { note in
            let matchesClass = selectedClassFilter == "All" || note.noteClass == selectedClassFilter
            let matchesSearch = searchText.isEmpty ||
                note.title.localizedStandardContains(searchText) ||
                (note.description?.localizedStandardContains(searchText) ?? false) ||
                (note.content?.localizedStandardContains(searchText) ?? false)
            return matchesClass && matchesSearch
        }
    }

    // MARK: - API Calls & Refresh

    @MainActor
    private func refreshAllData() async {
        do {
            async let fetchedNotesTask = APIClient.fetchNotes()
            async let fetchedClassesTask = APIClient.fetchClasses()

            let (fetchedNotes, fetchedClasses) = try await (fetchedNotesTask, fetchedClassesTask)

            self.notes = fetchedNotes
            self.classes = fetchedClasses
            if selectedClassFilter != "All", !fetchedClasses.contains(where: { $0.name == selectedClassFilter }) {
                selectedClassFilter = "All"
            }
            self.isLoading = false
            self.errorMessage = nil

            // Persist to local cache for instant cold start
            LocalDataCache.shared.saveNotes(fetchedNotes)
            LocalDataCache.shared.saveClasses(fetchedClasses)

            withAnimation(.easeInOut(duration: 0.25)) {
                self.isNetworkUnreachable = false
            }
        } catch {
            self.isLoading = false
            let isNetwork = (error as? APIError)?.isNetworkError == true || (error as? URLError) != nil || !NetworkMonitor.shared.isConnected

            withAnimation(.easeInOut(duration: 0.25)) {
                if isNetwork {
                    self.isNetworkUnreachable = true
                }
            }

            self.errorMessage = error.localizedDescription
        }
    }

    private func startBackgroundPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                guard !Task.isCancelled else { break }
                let hasProcessing = await MainActor.run { notes.contains { $0.isProcessing } }
                if hasProcessing {
                    if let updatedNotes = try? await APIClient.fetchNotes(), !Task.isCancelled {
                        await MainActor.run {
                            self.notes = updatedNotes
                            LocalDataCache.shared.saveNotes(updatedNotes)
                        }
                    }
                }
            }
        }
    }

    private func stopBackgroundPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    private func deleteNote(_ note: NoteItem) {
        Task {
            do {
                try await APIClient.deleteNote(id: note.id)
                await MainActor.run {
                    self.notes.removeAll { $0.id == note.id }
                    LocalDataCache.shared.removeNote(id: note.id)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func retryNote(_ note: NoteItem) {
        guard !retryingNoteIds.contains(note.id) else { return }
        retryingNoteIds.insert(note.id)
        Task {
            do {
                try await APIClient.retryNote(id: note.id)
                await refreshAllData()
                await MainActor.run {
                    _ = self.retryingNoteIds.remove(note.id)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    _ = self.retryingNoteIds.remove(note.id)
                }
            }
        }
    }

    private func assignClass(note: NoteItem, className: String?) {
        Task {
            do {
                try await APIClient.updateNoteClass(id: note.id, noteClass: className)
                await refreshAllData()
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
