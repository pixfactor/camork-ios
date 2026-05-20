import SwiftUI

/// 세션의 이름 + 메모를 한 화면에서 동시에 편집하는 시트 (Plan F — dogfood 통합).
///
/// 기존 `SessionNameEditSheet` + `SessionNoteEditSheet` 두 진입점이 분리되어 있던 흐름을
/// 한 sheet으로 합친다. 저장은 `SessionInfoEditor`가 단일 GRDB transaction으로 commit해
/// 부분 실패가 사용자에게 노출되지 않는다.
///
/// 검증 규칙은 editor와 동일:
/// - 이름: trim 후 빈 문자열이면 저장 차단 (`Error.emptyName` → 안내 alert).
/// - 메모: trim 없음. 빈 문자열은 nil로 normalize해서 column clear 의미로 처리.
struct SessionInfoEditSheet: View {
    let sessionId: UUID
    let initialName: String
    let initialNote: String?
    let editor: SessionInfoEditor
    let onSaved: (_ savedName: String, _ savedNote: String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var nameDraft: String
    @State private var noteDraft: String
    @State private var saveError: String?
    @State private var isSaving = false

    init(
        sessionId: UUID,
        initialName: String,
        initialNote: String?,
        editor: SessionInfoEditor,
        onSaved: @escaping (_ savedName: String, _ savedNote: String?) -> Void
    ) {
        self.sessionId = sessionId
        self.initialName = initialName
        self.initialNote = initialNote
        self.editor = editor
        self.onSaved = onSaved
        self._nameDraft = State(initialValue: initialName)
        self._noteDraft = State(initialValue: initialNote ?? "")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("session_name_field_label") {
                    TextField("session_name_field_label", text: $nameDraft)
                        .textInputAutocapitalization(.sentences)
                }
                Section("session_note_field_label") {
                    TextEditor(text: $noteDraft)
                        .frame(minHeight: 140)
                }
            }
            .navigationTitle("session_info_edit_title")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("button_cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("button_save") {
                        Task { await save() }
                    }
                    .disabled(isSaving || trimmedName.isEmpty)
                }
            }
        }
        .alert(
            "session_info_save_error_title",
            isPresented: errorBinding,
            presenting: saveError
        ) { _ in
            Button("button_ok", role: .cancel) { saveError = nil }
        } message: { message in
            Text(message)
        }
    }

    private var trimmedName: String {
        nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @MainActor
    private func save() async {
        guard !isSaving else { return }
        isSaving = true
        defer { isSaving = false }

        // 빈 문자열은 nil로 normalize — note 컬럼 clear는 nil로만 표현 (SessionNoteEditor와 동일 의미).
        let resolvedNote: String? = noteDraft.isEmpty ? nil : noteDraft

        do {
            try await editor.update(
                sessionId: sessionId,
                name: trimmedName,
                note: resolvedNote
            )
            onSaved(trimmedName, resolvedNote)
            dismiss()
        } catch SessionInfoEditor.Error.emptyName {
            saveError = String(localized: "session_name_empty_error")
        } catch SessionInfoEditor.Error.notFound {
            saveError = String(localized: "session_edit_not_found_error")
        } catch {
            saveError = String(describing: error)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { saveError != nil },
            set: { newValue in
                if !newValue { saveError = nil }
            }
        )
    }
}
