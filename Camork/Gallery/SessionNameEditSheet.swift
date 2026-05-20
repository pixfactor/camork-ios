import Foundation
import SwiftUI

/// Session name edit sheet (Plan C Phase 3.5).
struct SessionNameEditSheet: View {
    @Environment(\.dismiss) private var dismiss

    let sessionId: UUID
    let editor: SessionNameEditor
    let onSaved: (String) -> Void

    @State private var name: String
    @State private var showsEmptyNameError = false
    @State private var isSaving = false
    @State private var saveError: String?

    init(
        sessionId: UUID,
        initialName: String,
        editor: SessionNameEditor,
        onSaved: @escaping (String) -> Void
    ) {
        self.sessionId = sessionId
        self.editor = editor
        self.onSaved = onSaved
        self._name = State(initialValue: initialName)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("session_name_field_label", text: $name)
                    .textInputAutocapitalization(.words)

                if showsEmptyNameError {
                    Text("session_name_empty_error")
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle(Text("session_name_edit_title"))
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
        }
        .onChange(of: name) { _, newValue in
            if !newValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                showsEmptyNameError = false
            }
        }
        .alert(
            "session_name_save_error_title",
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
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            showsEmptyNameError = true
            return
        }

        isSaving = true
        defer { isSaving = false }

        do {
            try await editor.update(sessionId: sessionId, name: name)
            onSaved(trimmed)
            dismiss()
        } catch SessionNameEditor.Error.emptyName {
            showsEmptyNameError = true
        } catch SessionNameEditor.Error.notFound {
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
