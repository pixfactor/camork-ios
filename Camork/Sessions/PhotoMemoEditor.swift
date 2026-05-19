import Foundation

/// Photo 메모 편집 도메인 helper. UI 사용처 (Phase 3.2 PhotoDetailView)가
/// MediaStorage actor를 직접 호출하지 않고 본 thin wrapper를 거치도록 강제 —
/// notFound 같은 도메인 에러를 actor API에 누적시키지 않는다.
///
/// **MediaStorage API 변경 없음**: 본 구현은 기존 `fetchPhoto(id:)` + `updatePhotoNote(photoId:note:)`
/// 두 메서드를 차례로 호출. 두 await 사이의 micro race (다른 컨텍스트가 photo를
/// 삭제하는 경우)는 v1 Core 단일 사용자/단일 디바이스 환경에서 무시 가능하며,
/// 발생 시 update가 silent no-op이 되어 데이터 손상은 없다.
struct PhotoMemoEditor: Sendable {
    enum Error: Swift.Error, Sendable, Equatable {
        case notFound
    }

    let mediaStorage: MediaStorage

    init(mediaStorage: MediaStorage) {
        self.mediaStorage = mediaStorage
    }

    /// note를 `nil`로 설정하면 메모를 clear. 존재하지 않는 photoId는
    /// `Error.notFound`로 throw — UI는 본 케이스를 catch해 "이미 삭제된 사진" 안내 등
    /// 분기 가능.
    func update(photoId: UUID, note: String?) async throws {
        guard try await mediaStorage.fetchPhoto(id: photoId) != nil else {
            throw Error.notFound
        }
        try await mediaStorage.updatePhotoNote(photoId: photoId, note: note)
    }
}
