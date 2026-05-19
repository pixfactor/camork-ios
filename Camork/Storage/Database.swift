import Foundation
import GRDB

/// Camork 메타데이터 DB 진입점. v1 Core는 단일 `DatabaseQueue`로 충분 (ADR #1).
enum CamorkDatabase {

    /// production과 test가 공유하는 단일 GRDB Configuration 소스 (ADR #10).
    /// - WAL journal_mode + foreign_keys ON.
    static func makeConfiguration() -> Configuration {
        var config = Configuration()
        config.prepareDatabase { db in
            try db.execute(sql: "PRAGMA journal_mode = WAL")
            try db.execute(sql: "PRAGMA foreign_keys = ON")
        }
        return config
    }

    /// App startup에서 호출. Library/Application Support/Camork/Metadata/camork.sqlite를
    /// 열고 migration v1을 적용한다.
    ///
    /// - ADR #12: isExcludedFromBackup + Data Protection을
    ///   metaDir → open+migrate → sqlite/wal/shm 순서로 적용.
    static func open() throws -> DatabaseQueue {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        var metaDir = appSupport.appendingPathComponent("Camork/Metadata", isDirectory: true)
        try FileManager.default.createDirectory(at: metaDir, withIntermediateDirectories: true)

        // 디렉토리에 backup exclusion + Data Protection 먼저 (파일 생성 전)
        var dirValues = URLResourceValues()
        dirValues.isExcludedFromBackup = true
        try metaDir.setResourceValues(dirValues)
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: metaDir.path
        )

        let dbURL = metaDir.appendingPathComponent("camork.sqlite")
        let queue = try DatabaseQueue(path: dbURL.path, configuration: makeConfiguration())
        try Migrations.makeMigrator().migrate(queue)

        // open + migrate 후 sqlite + WAL + SHM 사이드카에 attribute 적용 (존재 시)
        let sidecarNames = ["camork.sqlite", "camork.sqlite-wal", "camork.sqlite-shm"]
        for name in sidecarNames {
            var url = metaDir.appendingPathComponent(name)
            guard FileManager.default.fileExists(atPath: url.path) else { continue }
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try url.setResourceValues(values)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: url.path
            )
        }

        return queue
    }
}
