import Foundation

/// Session 이름 편집 도메인 helper (Plan C Phase 1.3). PhotoMemoEditor 패턴 mirror.
///
/// 책임:
/// - 빈/whitespace-only 이름은 DB 도달 전에 `Error.emptyName`으로 차단 (도메인 invariant).
/// - 양쪽 공백 trim 후 trimmed name으로 `MediaStorage.updateSessionName` 호출.
/// - `MediaStorage.Error.sessionNotFound`를 `Error.notFound`로 매핑 — UI는 본 case로
///   "이미 삭제된 세션" 분기 가능.
struct SessionNameEditor: Sendable {
    enum Error: Swift.Error, Sendable, Equatable {
        case notFound
        case emptyName
    }

    let mediaStorage: MediaStorage

    init(mediaStorage: MediaStorage) {
        self.mediaStorage = mediaStorage
    }

    func update(sessionId: UUID, name: String) async throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw Error.emptyName
        }
        do {
            try await mediaStorage.updateSessionName(sessionId: sessionId, name: trimmed)
        } catch MediaStorage.Error.sessionNotFound {
            throw Error.notFound
        }
    }
}
