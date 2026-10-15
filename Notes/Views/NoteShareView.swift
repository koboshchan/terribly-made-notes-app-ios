import SwiftUI

struct NoteShareView: View {
    let note: NoteItem
    @State private var model: NoteSharingModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    init(note: NoteItem, model: NoteSharingModel? = nil) {
        self.note = note
        _model = State(initialValue: model ?? NoteSharingModel(noteId: note.id))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(note.title, systemImage: "doc.text")
                        .font(.headline)
                }
                Section {
                    if model.isWorking {
                        ProgressView("Updating sharing…")
                    } else if !model.hasLoaded {
                        Button("Load Sharing Settings", systemImage: "arrow.clockwise") {
                            Task { await model.load() }
                        }
                    } else if let url = model.info?.activeURL {
                        Label("Public link is on", systemImage: "link")
                        Text(url.absoluteString)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .accessibilityLabel("Public link, \(url.absoluteString)")
                        ShareLink(item: url, subject: Text(note.title)) {
                            Label("Share Link", systemImage: "square.and.arrow.up")
                        }
                        Button("Copy Link", systemImage: "doc.on.doc") {
                            UIPasteboard.general.setItems([["public.url": url]], options: [.localOnly: true])
                            model.statusMessage = "Link copied."
                        }
                        if let expiration = model.info?.expiration {
                            LabeledContent("Expires", value: expiration.formatted(date: .abbreviated, time: .shortened))
                        }
                        if model.info?.shareAllowChat == true {
                            Text("AI chat is enabled for this existing link and uses your account's quota.")
                                .font(.footnote)
                        }
                    } else {
                        Label("Not publicly shared", systemImage: "lock")
                        Button("Enable Public Link", systemImage: "link.badge.plus") {
                            Task { await model.enable() }
                        }
                        .disabled(!note.isCompleted)
                    }
                } header: {
                    Text("Public link")
                } footer: {
                    Text("Anyone with the link can read this note without signing in. Links cannot be disabled in this app yet. New links have AI chat turned off.")
                }

                Section {
                    ShareLink(item: export.text, subject: Text(note.title)) {
                        Label("Share Note Text", systemImage: "text.alignleft")
                    }
                    ShareLink(item: export, preview: SharePreview(note.title, image: Image(systemName: "doc.text"))) {
                        Label("Export Markdown", systemImage: "doc.badge.arrow.up")
                    }
                } header: {
                    Text("Send a copy")
                } footer: {
                    Text("Includes notes, flashcards, and quiz answers. Copies stay with recipients and cannot be recalled.")
                }

                if let error = model.errorMessage {
                    Section {
                        Text(error).foregroundStyle(.red)
                        Button("Retry", systemImage: "arrow.clockwise") { Task { await model.load() } }
                    }
                }
                if let status = model.statusMessage {
                    Section { Text(status).foregroundStyle(.secondary).accessibilityIdentifier("sharingStatus") }
                }
            }
            .navigationTitle("Share Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
            .task { await model.load() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await model.load() } }
            }
        }
    }

    private var export: NoteMarkdownExport { NoteMarkdownExport(note: note) }
}
