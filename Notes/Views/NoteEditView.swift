import SwiftUI

/// Plain text editor used for correcting a note (title + Markdown) or a transcript.
struct TextCorrectionView: View {
    let title: String
    let showsTitleField: Bool
    @State var editedTitle: String
    @State var text: String
    let onSave: @MainActor (_ title: String, _ text: String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSaving = false
    @State private var errorMessage: String?

    private var canSave: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!showsTitleField || !editedTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if showsTitleField {
                    TextField("Title", text: $editedTitle)
                        .font(.headline)
                        .padding()
                    Divider()
                }
                TextEditor(text: $text)
                    .font(.body.monospaced())
                    .padding(.horizontal, 8)
                    .accessibilityLabel(title)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .padding()
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .interactiveDismissDisabled(isSaving)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }.disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isSaving {
                        ProgressView()
                    } else {
                        Button("Save") { save() }.disabled(!canSave)
                    }
                }
            }
        }
    }

    private func save() {
        isSaving = true
        errorMessage = nil
        Task {
            do {
                try await onSave(editedTitle, text)
                dismiss()
            } catch {
                errorMessage = error.localizedDescription
            }
            isSaving = false
        }
    }
}
