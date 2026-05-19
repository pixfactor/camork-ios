import Foundation
@testable import Camork

/// Failure matrix 테스트용 `FileOps` 가짜 구현. 호출 횟수 / 실패 주입을 통해 결정적
/// 시나리오를 만든다 (ADR #10 단위 테스트 전략 + Plan B Phase 1.6).
///
/// - `writeStaging` / `moveStagingToFinal`은 `failOn`이 지정된 경우 즉시 throw.
/// - `removeStaging` / `removeFinal`은 cleanup 호출 횟수만 카운트 (실제 best-effort
///   호출 시 throw하지 않는 production 동작과 동일).
/// - in-memory store만 사용 — 실제 파일 시스템 접근 없음.
enum FakeFileOpsOperation: Sendable {
    case writeStaging
    case moveStagingToFinal
}

enum FakeFileOpsError: Error, Sendable {
    case simulated(FakeFileOpsOperation)
}

final class FakeFileOps: FileOps, @unchecked Sendable {
    let failOn: FakeFileOpsOperation?

    private let lock = NSLock()
    private var stagingStore: Set<String> = []
    private var finalStore: Set<String> = []
    private var _stagingCleanupCount = 0
    private var _finalRemoveCount = 0

    init(failOn: FakeFileOpsOperation? = nil) {
        self.failOn = failOn
    }

    var stagingCleanupCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _stagingCleanupCount
    }

    var finalRemoveCount: Int {
        lock.lock(); defer { lock.unlock() }
        return _finalRemoveCount
    }

    func writeStaging(fileName: String, data: Data) throws {
        if failOn == .writeStaging { throw FakeFileOpsError.simulated(.writeStaging) }
        lock.lock(); defer { lock.unlock() }
        stagingStore.insert(fileName)
    }

    func moveStagingToFinal(fileName: String) throws {
        if failOn == .moveStagingToFinal { throw FakeFileOpsError.simulated(.moveStagingToFinal) }
        lock.lock(); defer { lock.unlock() }
        stagingStore.remove(fileName)
        finalStore.insert(fileName)
    }

    func removeStaging(fileName: String) throws {
        lock.lock(); defer { lock.unlock() }
        _stagingCleanupCount += 1
        stagingStore.remove(fileName)
    }

    func removeFinal(fileName: String) throws {
        lock.lock(); defer { lock.unlock() }
        _finalRemoveCount += 1
        finalStore.remove(fileName)
    }

    func stagingExists(fileName: String) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        return stagingStore.contains(fileName)
    }

    func finalExists(fileName: String) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        return finalStore.contains(fileName)
    }

    func enumerateFinal() throws -> [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(finalStore)
    }
}
