import Foundation
@testable import Camork

/// Failure matrix 테스트용 `FileOps` 가짜 구현. 호출 횟수 / 실패 주입을 통해 결정적
/// 시나리오를 만든다 (ADR #10 단위 테스트 전략 + Plan B Phase 1.6).
///
/// - `writeStaging` / `moveStagingToFinal`은 `failOn`이 지정된 경우 즉시 throw.
/// - `removeStaging` / `removeFinal`은 cleanup 호출 횟수만 카운트 (실제 best-effort
///   호출 시 throw하지 않는 production 동작과 동일).
/// - in-memory `[fileName: Data]` store만 사용 — 실제 파일 시스템 접근 없음.
///   readFinal (Phase 3.2)이 추가되며 staging/final 저장소가 Set에서 Dict으로 확장.
enum FakeFileOpsOperation: Sendable {
    case writeStaging
    case moveStagingToFinal
}

enum FakeFileOpsError: Error, Sendable {
    case simulated(FakeFileOpsOperation)
    case fileNotFound(fileName: String)
}

final class FakeFileOps: FileOps, @unchecked Sendable {
    let failOn: FakeFileOpsOperation?

    private let lock = NSLock()
    private var stagingContents: [String: Data] = [:]
    private var finalContents: [String: Data] = [:]
    private var thumbContents: [String: Data] = [:]
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
        stagingContents[fileName] = data
    }

    func moveStagingToFinal(fileName: String) throws {
        if failOn == .moveStagingToFinal { throw FakeFileOpsError.simulated(.moveStagingToFinal) }
        lock.lock(); defer { lock.unlock() }
        if let data = stagingContents.removeValue(forKey: fileName) {
            finalContents[fileName] = data
        } else {
            // production parity: mv는 staging이 없으면 OS-level error를 raise. 본 fake는
            // 기본 시나리오에서 saveCapture가 항상 writeStaging 후 mv 호출 — 도달 불가
            finalContents[fileName] = Data()
        }
    }

    func removeStaging(fileName: String) throws {
        lock.lock(); defer { lock.unlock() }
        _stagingCleanupCount += 1
        stagingContents.removeValue(forKey: fileName)
    }

    func removeFinal(fileName: String) throws {
        lock.lock(); defer { lock.unlock() }
        _finalRemoveCount += 1
        finalContents.removeValue(forKey: fileName)
    }

    func stagingExists(fileName: String) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        return stagingContents.keys.contains(fileName)
    }

    func finalExists(fileName: String) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        return finalContents.keys.contains(fileName)
    }

    func enumerateFinal() throws -> [String] {
        lock.lock(); defer { lock.unlock() }
        return Array(finalContents.keys)
    }

    func readFinal(fileName: String) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard let data = finalContents[fileName] else {
            throw FakeFileOpsError.fileNotFound(fileName: fileName)
        }
        return data
    }

    // MARK: - Thumbnail cache (Plan C Phase 2.1)

    func writeThumb(fileName: String, data: Data) throws {
        lock.lock(); defer { lock.unlock() }
        thumbContents[fileName] = data
    }

    func readThumb(fileName: String) throws -> Data {
        lock.lock(); defer { lock.unlock() }
        guard let data = thumbContents[fileName] else {
            throw FakeFileOpsError.fileNotFound(fileName: fileName)
        }
        return data
    }

    func removeThumb(fileName: String) throws {
        lock.lock(); defer { lock.unlock() }
        thumbContents.removeValue(forKey: fileName)
    }
}
