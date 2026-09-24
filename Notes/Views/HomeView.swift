import SwiftUI
import ClerkKitUI

public struct HomeView: View {
    @State private var notes: [NoteItem] = []
    @State private var classes: [UserClass] = []
    @State private var selectedClassFilter: String = "All"
    @State private var searchText = ""
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showRecordSheet = false
    @State private var showClassesSheet = false
    @State private var retryingNoteIds: Set<String> = []
    @State private var noteToAssignClass: NoteItem?

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }

                if filteredNotes.isEmpty && !isLoading {
                    ContentUnavailableView(
                        searchText.isEmpty ? "No Notes Found" : "No Matching Notes",
                        systemImage: searchText.isEmpty ? "note.text.badge.plus" : "magnifyingglass",
                        description: Text(searchText.isEmpty ? "Record or import an audio file to create your first note." : "Try a different search term or class filter.")
                    )
                }

                ForEach(filteredNotes) { note in
                    NavigationLink(value: note.id) {
                        noteRow(note: note)
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteNote(note)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }

                        if !classes.isEmpty {
                            Button {
                                noteToAssignClass = note
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
                        }
                    }
                }
            }
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

                        Divider()

                        Button {
                            showClassesSheet = true
                        } label: {
                            Label("Manage Classes...", systemImage: "folder.badge.gearshape")
                        }
                    } label: {
                        Image(systemName: selectedClassFilter == "All" ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }

                    // New Note Button
                    Button {
                        showRecordSheet = true
                    } label: {
                        Label("New Note", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showRecordSheet) {
                RecordNoteView { _ in
                    loadData()
                }
            }
            .sheet(isPresented: $showClassesSheet) {
                ClassesView()
            }
            .confirmationDialog(
                "Assign Class",
                isPresented: Binding(
                    get: { noteToAssignClass != nil },
                    set: { if !$0 { noteToAssignClass = nil } }
                ),
                titleVisibility: .visible
            ) {
                Button("None (Remove Class)") {
                    if let note = noteToAssignClass {
                        assignClass(note: note, className: nil)
                    }
                }
                ForEach(classes) { cls in
                    Button(cls.name) {
                        if let note = noteToAssignClass {
                            assignClass(note: note, className: cls.name)
                        }
                    }
                }
                Button("Cancel", role: .cancel) {}
            }
            .refreshable {
                loadData()
            }
            .task {
                loadData()
                loadClasses()
                startBackgroundPolling()
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

    // MARK: - API Calls

    private func loadData() {
        Task {
            do {
                let fetched = try await APIClient.fetchNotes()
                await MainActor.run {
                    self.notes = fetched
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
            if let fetchedClasses = try? await APIClient.fetchClasses() {
                await MainActor.run {
                    self.classes = fetchedClasses
                }
            }
        }
    }

    private func startBackgroundPolling() {
        Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                let hasProcessing = notes.contains { $0.isProcessing }
                if hasProcessing {
                    if let updatedNotes = try? await APIClient.fetchNotes() {
                        await MainActor.run {
                            self.notes = updatedNotes
                        }
                    }
                }
            }
        }
    }

    private func deleteNote(_ note: NoteItem) {
        Task {
            do {
                try await APIClient.deleteNote(id: note.id)
                await MainActor.run {
                    self.notes.removeAll { $0.id == note.id }
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    private func retryNote(_ note: NoteItem) {
        retryingNoteIds.insert(note.id)
        Task {
            do {
                try await APIClient.retryNote(id: note.id)
                loadData()
                await MainActor.run {
                    self.retryingNoteIds.remove(note.id)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.retryingNoteIds.remove(note.id)
                }
            }
        }
    }

    private func assignClass(note: NoteItem, className: String?) {
        Task {
            do {
                try await APIClient.updateNoteClass(id: note.id, noteClass: className)
                loadData()
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
