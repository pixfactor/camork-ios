import Foundation

/// 파일 IO 추상 (test seam).
///
/// production은 `MediaFileSystem`, test는 `FakeFileOps`로 staging write / mv /
/// final-delete 실패를 강제할 수 있다 (Phase 1.6 failure matrix 테스트).
///
/// v1.2 C5: 명명은 `stagingExists` / `finalExists`로 통일 (이전 변종
/// `stagingDataExists`/`finalDataExists`는 v1.2에서 모두 정정 — 단일 canonical).
protocol FileOps: Sendable {
    func writeStaging(fileName: String, data: Data) throws
    func moveStagingToFinal(fileName: String) throws
    func removeStaging(fileName: String) throws
    func removeFinal(fileName: String) throws
    func stagingExists(fileName: String) throws -> Bool
    func finalExists(fileName: String) throws -> Bool
    func enumerateFinal() throws -> [String]
}
