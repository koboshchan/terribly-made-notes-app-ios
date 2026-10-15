import SwiftUI

public struct ClassesView: View {
    @State private var classes: [UserClass] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showAddClassDialog = false
    @State private var newClassName = ""
    @State private var newClassDescription = ""
    @State private var isCreating = false
    @State private var classToDelete: UserClass?
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }

                if isLoading && classes.isEmpty {
                    ProgressView("Loading classes…").frame(maxWidth: .infinity)
                } else if classes.isEmpty && errorMessage == nil {
                    ContentUnavailableView(
                        "No Classes Yet",
                        systemImage: "folder.badge.plus",
                        description: Text("Classes help organize notes by course or subject.")
                    )
                }

                ForEach(classes) { cls in
                    HStack(spacing: 16) {
                        Image(systemName: "folder.fill")
                            .foregroundStyle(NotebookStyle.accent)
                            .font(.title2)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                        Text(cls.name)
                            .font(.headline)
                        if let desc = cls.description, !desc.isEmpty {
                            Text(desc)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        }
                    }
                    .padding(.vertical, 10)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            classToDelete = cls
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(NotebookStyle.canvas)
            .tint(NotebookStyle.accent)
            .navigationTitle("Manage Classes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddClassDialog = true
                    } label: {
                        Label("Add Class", systemImage: "plus")
                    }
                    .disabled(isCreating)
                }
            }
            .alert("New Class", isPresented: $showAddClassDialog) {
                TextField("Class Name (e.g. Physics 101)", text: $newClassName)
                TextField("Description (optional)", text: $newClassDescription)
                Button("Create") {
                    createNewClass()
                }
                .disabled(newClassName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
                Button("Cancel", role: .cancel) {
                    newClassName = ""
                    newClassDescription = ""
                }
            }
            .overlay {
                if isCreating { ProgressView("Creating class…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) }
            }
            .confirmationDialog("Delete Class?", isPresented: Binding(
                get: { classToDelete != nil },
                set: { if !$0 { classToDelete = nil } }
            ), titleVisibility: .visible, presenting: classToDelete) { cls in
                Button("Delete Class", role: .destructive) { deleteClass(cls) }
                Button("Cancel", role: .cancel) { classToDelete = nil }
            } message: { cls in
                Text("Delete “\(cls.name)” from your classes?")
            }
            .refreshable {
                await loadClasses()
            }
            .task {
                await loadClasses()
            }
        }
    }

    @MainActor
    private func loadClasses() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            classes = try await APIClient.fetchClasses()
            LocalDataCache.shared.saveClasses(classes)
        } catch {
            guard !Task.isCancelled else { return }
            errorMessage = error.localizedDescription
        }
    }

    private func createNewClass() {
        let name = newClassName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !isCreating else { return }

        let desc = newClassDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        isCreating = true

        Task {
            do {
                let created = try await APIClient.createClass(name: name, description: desc.isEmpty ? nil : desc)
                await MainActor.run {
                    self.classes.append(created)
                    LocalDataCache.shared.saveClasses(self.classes)
                    self.newClassName = ""
                    self.newClassDescription = ""
                    self.isCreating = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                    self.isCreating = false
                }
            }
        }
    }

    private func deleteClass(_ cls: UserClass) {
        Task {
            do {
                try await APIClient.deleteClass(id: cls.id)
                await MainActor.run {
                    self.classes.removeAll { $0.id == cls.id }
                    LocalDataCache.shared.saveClasses(self.classes)
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
