import Foundation
import SwiftUI

/// Session note edit sheet (Plan C Phase 3.5).
struct SessionNoteEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let sessionId: UUID
    let editor: SessionNoteEditor
    let onSaved: (String?) -> Void

    @State private var note: String
    @State private var isSaving = false
    @State private var saveError: String?

    init(
        sessionId: UUID,
        initialNote: String?,
        editor: SessionNoteEditor,
        onSaved: @escaping (String?) -> Void
    ) {
        self.sessionId = sessionId
        self.editor = editor
        self.onSaved = onSaved
        self._note = State(initialValue: initialNote ?? "")
    }

    var body: some View {
        NavigationStack {
            TextEditor(text: $note)
                .padding(Spacing.md)
                .navigationTitle(Text("session_note_edit_title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("button_cancel") {
                            dismiss()
                        }
                        .disabled(isSaving)
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("button_save") {
                            Task { await save() }
                        }
                        .disabled(isSaving)
                    }
                }
                .accessibilityLabel(Text("session_note_field_label"))
        }
        .alert(
            "session_note_save_error_title",
            isPresented: saveErrorBinding,
            presenting: saveError
        ) { _ in
            Button("button_ok", role: .cancel) { saveError = nil }
        } message: { message in
            Text(message)
        }
    }

    @MainActor
    private func save() async {
        let resolvedNote: String? = note.isEmpty ? nil : note

        isSaving = true
        defer { isSaving = false }

        do {
            try await editor.update(sessionId: sessionId, note: resolvedNote)
            onSaved(resolvedNote)
            dismiss()
        } catch SessionNoteEditor.Error.notFound {
            saveError = String(localized: "session_edit_not_found_error")
        } catch {
            saveError = String(describing: error)
        }
    }

    private var saveErrorBinding: Binding<Bool> {
        Binding(
            get: { saveError != nil },
            set: { newValue in
                if !newValue { saveError = nil }
            }
        )
    }
}
