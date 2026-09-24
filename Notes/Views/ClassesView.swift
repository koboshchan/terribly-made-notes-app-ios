import SwiftUI

public struct ClassesView: View {
    @State private var classes: [UserClass] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var showAddClassDialog = false
    @State private var newClassName = ""
    @State private var newClassDescription = ""
    @State private var isCreating = false

    public init() {}

    public var body: some View {
        NavigationStack {
            List {
                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                }

                if classes.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No Classes Yet",
                        systemImage: "folder.badge.plus",
                        description: Text("Classes help organize notes by course or subject.")
                    )
                }

                ForEach(classes) { cls in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(cls.name)
                            .font(.headline)
                        if let desc = cls.description, !desc.isEmpty {
                            Text(desc)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            deleteClass(cls)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .navigationTitle("Manage Classes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showAddClassDialog = true
                    } label: {
                        Label("Add Class", systemImage: "plus")
                    }
                }
            }
            .alert("New Class", isPresented: $showAddClassDialog) {
                TextField("Class Name (e.g. Physics 101)", text: $newClassName)
                TextField("Description (optional)", text: $newClassDescription)
                Button("Create") {
                    createNewClass()
                }
                Button("Cancel", role: .cancel) {
                    newClassName = ""
                    newClassDescription = ""
                }
            }
            .refreshable {
                loadClasses()
            }
            .task {
                loadClasses()
            }
        }
    }

    private func loadClasses() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let fetched = try await APIClient.fetchClasses()
                await MainActor.run {
                    self.classes = fetched
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

    private func createNewClass() {
        let name = newClassName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }

        let desc = newClassDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        isCreating = true

        Task {
            do {
                let created = try await APIClient.createClass(name: name, description: desc.isEmpty ? nil : desc)
                await MainActor.run {
                    self.classes.append(created)
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
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }
}
