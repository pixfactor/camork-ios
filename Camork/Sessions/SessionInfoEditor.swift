import Foundation

/// 세션의 이름 + 메모를 한 번에 편집하는 도메인 helper (Plan F — dogfood 1차 통합).
///
/// SessionNameEditor + SessionNoteEditor 패턴을 따르되, 본 helper는 두 값을
/// 하나의 `MediaStorage.updateSessionInfo` 호출(단일 GRDB transaction)로 commit해
/// 부분 실패(이름은 저장 / 메모는 실패) 가능성을 제거한다. UI는 합쳐진 sheet 하나로
/// 진입하므로 사용자에게 두 commit이 보이지 않게 한다.
///
/// 검증 정책:
/// - **name**: trim 후 빈 문자열이면 `Error.emptyName` (SessionNameEditor와 동일).
/// - **note**: trim 안 함, `nil`만 clear로 해석 (SessionNoteEditor와 동일).
struct SessionInfoEditor: Sendable {
    enum Error: Swift.Error, Sendable, Equatable {
        case notFound
        case emptyName
    }

    let mediaStorage: MediaStorage

    init(mediaStorage: MediaStorage) {
        self.mediaStorage = mediaStorage
    }

    func update(sessionId: UUID, name: String, note: String?) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw Error.emptyName
        }
        do {
            try await mediaStorage.updateSessionInfo(
                sessionId: sessionId,
                name: trimmed,
                note: note
            )
        } catch MediaStorage.Error.sessionNotFound {
            throw Error.notFound
        }
    }
}
