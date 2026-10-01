import SwiftUI

/// Create, copy, rotate or revoke the read-only share link for one note.
struct NoteShareView: View {
    let noteId: String
    @Environment(\.dismiss) private var dismiss

    @State private var info: APIClient.ShareInfo?
    @State private var expiresInDays = 30
    @State private var allowChat = false
    @State private var isWorking = true
    @State private var errorMessage: String?
    @State private var confirmRevoke = false

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
                        if let expiry = info?.shareExpiresAt.flatMap(Self.parseDate) {
                            LabeledContent("Expires", value: expiry.formatted(date: .abbreviated, time: .omitted))
                        }
                    }
                }

                Section {
                    Picker("Expires after", selection: $expiresInDays) {
                        Text("1 day").tag(1)
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                        Text("90 days").tag(90)
                        Text("1 year").tag(365)
                    }
                    Toggle("Allow viewers to Ask AI", isOn: $allowChat)
                } footer: {
                    Text("Anyone with the link can read this note. Ask AI uses your account's quota.")
                }

                Section {
                    Button(activeURL == nil ? "Create Link" : "Update Link") { save(rotate: false) }
                    if activeURL != nil {
                        Button("New Link (old one stops working)") { save(rotate: true) }
                        Button("Stop Sharing", role: .destructive) { confirmRevoke = true }
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
            .confirmationDialog("Stop sharing?", isPresented: $confirmRevoke, titleVisibility: .visible) {
                Button("Stop Sharing", role: .destructive) { revoke() }
            } message: {
                Text("The current link will stop working.")
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

    private func save(rotate: Bool) {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                info = try await APIClient.createShare(id: noteId, expiresInDays: expiresInDays, allowChat: allowChat, rotate: rotate)
            } catch {
                errorMessage = error.localizedDescription
            }
            isWorking = false
        }
    }

    private func revoke() {
        isWorking = true
        errorMessage = nil
        Task {
            do {
                try await APIClient.revokeShare(id: noteId)
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
