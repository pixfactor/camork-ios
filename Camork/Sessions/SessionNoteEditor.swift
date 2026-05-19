import Foundation

/// Session 메모 편집 도메인 helper (Plan C Phase 1.3). PhotoMemoEditor 패턴 mirror.
///
/// 책임:
/// - `note=nil` 만이 메모를 clear. 빈 문자열은 그대로 저장 (SessionNameEditor가
///   이름의 빈 값을 차단하는 것과 달리, 메모는 사용자 의도에 따른 공백/빈 상태도
///   보존). trim 없음.
/// - `MediaStorage.Error.sessionNotFound`를 `Error.notFound`로 매핑.
struct SessionNoteEditor: Sendable {
    enum Error: Swift.Error, Sendable, Equatable {
        case notFound
    }

    let mediaStorage: MediaStorage

    init(mediaStorage: MediaStorage) {
        self.mediaStorage = mediaStorage
    }

    func update(sessionId: UUID, note: String?) async throws {
        do {
            try await mediaStorage.updateSessionNote(sessionId: sessionId, note: note)
        } catch MediaStorage.Error.sessionNotFound {
            throw Error.notFound
        }
    }
}
