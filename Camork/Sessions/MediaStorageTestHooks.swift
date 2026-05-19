#if DEBUG
import Foundation

/// MediaStorage 결정적 race/failure 테스트용 ordering gates (S2/v1.2). 파일 IO 실패
/// 주입은 `FileOps` protocol(`FakeFileOps`)로 위임, 본 hooks는 순서 제어 전용.
///
/// throws 시 saveCapture catch block을 통해 cleanup 경로(Step 2/3/4 failure
/// matrix)로 진입 — DB commit failure 시뮬레이션도 본 hook에서 throw로 트리거.
struct MediaStorageTestHooks: Sendable {
    var afterManualFlagSnapshot: (@Sendable () async throws -> Void)?
    var beforeDBCommit: (@Sendable () async throws -> Void)?
}
#endif
