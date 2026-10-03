import SwiftUI

/// Create, copy, update or delete the read-only share link for one note.
struct NoteShareView: View {
    let noteId: String
    @Environment(\.dismiss) private var dismiss

    @State private var info: APIClient.ShareInfo?
    @State private var allowChat = false
    @State private var isWorking = true
    @State private var errorMessage: String?
    @State private var confirmDelete = false

    private var activeURL: URL? {
        guard info?.shareEnabled == true, let s = info?.shareUrl else { return nil }
        return URL(string: s)
    }

    var body: some View {
        NavigationStack {
            Form {
                if let url = activeURL {
                    Section("Link") {
                        ShareLink(item: url) {
                            Label(url.absoluteString, systemImage: "link")
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Button {
                            UIPasteboard.general.url = url
                        } label: {
                            Label("Copy Link", systemImage: "doc.on.doc")
                        }
                        LabeledContent("Expires", value: info?.shareExpiresAt.flatMap(Self.parseDate)?.formatted(date: .abbreviated, time: .omitted) ?? "Never")
                    }
                }

                Section {
                    Toggle("Allow viewers to Ask AI", isOn: $allowChat)
                } footer: {
                    Text("Anyone with the link can read this note. Ask AI uses your account's quota.")
                }

                Section {
                    Button(activeURL == nil ? "Create Link" : "Update Link") { save() }
                    if activeURL != nil {
                        Button("Delete Share Link", role: .destructive) { confirmDelete = true }
                    }
                }
                .disabled(isWorking)

                if let errorMessage {
                    Section { Text(errorMessage).foregroundStyle(.red) }
                }
            }
            .overlay { if isWorking && info == nil { ProgressView() } }
            .navigationTitle("Share Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .confirmationDialog("Delete share link?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete Share Link", role: .destructive) { deleteLink() }
            } message: {
                Text("The link will stop working. Your note is not deleted.")
            }
            .task { await load() }
        }
    }

    private func load() async {
        do {
            let fetched = try await APIClient.fetchShare(id: noteId)
            info = fetched
            allowChat = fetched.shareAllowChat ?? false
        } catch {
            errorMessage = error.localizedDescription
        }
        isWorking = false
    }

    private func save() {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                info = try await APIClient.createShare(id: noteId, allowChat: allowChat)
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func deleteLink() {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await APIClient.deleteShare(id: noteId)
                info = nil
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private static func parseDate(_ s: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: s) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)
    }
}
