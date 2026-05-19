import Testing
import GRDB
@testable import Camork

@Suite("Migrations")
struct MigrationsTests {
    @Test("migration v1 두 번 호출해도 appliedMigrations 동일 (Array — 등록 순서 보존)")
    func idempotent() throws {
        let db = try DatabaseQueue()
        let migrator = Migrations.makeMigrator()

        try migrator.migrate(db)
        let first = try db.read { try migrator.appliedMigrations($0) }

        try migrator.migrate(db)
        let second = try db.read { try migrator.appliedMigrations($0) }

        #expect(first == second)
        #expect(first == ["v1"])
    }

    @Test("v1 schema 생성 후 Session/Photo 테이블 존재")
    func schemaCreated() throws {
        let db = try DatabaseQueue()
        try Migrations.makeMigrator().migrate(db)

        try db.read { row in
            let tables = try Row.fetchAll(row, sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name")
                .compactMap { $0["name"] as String? }
            #expect(tables.contains("Session"))
            #expect(tables.contains("Photo"))
        }
    }

    @Test("Photo.kind에 'video' insert 시 CHECK 제약으로 실패")
    func checkConstraint() throws {
        let db = try DatabaseQueue()
        try Migrations.makeMigrator().migrate(db)

        #expect(throws: DatabaseError.self) {
            try db.write { row in
                try row.execute(sql: """
                    INSERT INTO Session(id, name, createdAt) VALUES('s1','test',0);
                    INSERT INTO Photo(id, sessionId, fileName, kind, capturedAt)
                    VALUES('p1','s1','x.heic','video',0);
                    """)
            }
        }
    }

    @Test("FK enforcement on — PRAGMA foreign_keys 활성화 (production config)")
    func foreignKeysEnforced() throws {
        let db = try DatabaseQueue(configuration: CamorkDatabase.makeConfiguration())
        try Migrations.makeMigrator().migrate(db)
        let fk: Int = try db.read { try Int.fetchOne($0, sql: "PRAGMA foreign_keys") ?? 0 }
        #expect(fk == 1)
    }

    @Test("CASCADE: Session 삭제 시 Photo도 삭제 (production config)")
    func cascadeDelete() throws {
        let db = try DatabaseQueue(configuration: CamorkDatabase.makeConfiguration())
        try Migrations.makeMigrator().migrate(db)
        try db.write { row in
            try row.execute(sql: """
                INSERT INTO Session(id, name, createdAt) VALUES('s1','test',0);
                INSERT INTO Photo(id, sessionId, fileName, kind, capturedAt)
                VALUES('p1','s1','x.heic','photo',0);
                """)
            try row.execute(sql: "DELETE FROM Session WHERE id='s1'")
            let count: Int = try Int.fetchOne(row, sql: "SELECT COUNT(*) FROM Photo") ?? -1
            #expect(count == 0)
        }
    }
}
