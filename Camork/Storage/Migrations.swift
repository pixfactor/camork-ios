import GRDB

/// GRDB DatabaseMigrator 빌더. 테스트는 `appliedMigrations(_:) -> [String]`로 검증 (ADR #10).
enum Migrations {
    static func makeMigrator() -> DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1") { db in
            try db.execute(sql: """
                CREATE TABLE Session (
                    id TEXT PRIMARY KEY,
                    name TEXT NOT NULL,
                    note TEXT,
                    createdAt INTEGER NOT NULL,
                    endedAt INTEGER,
                    firstLat REAL,
                    firstLon REAL,
                    firstHorizontalAccuracy REAL,
                    firstPlaceName TEXT,
                    deletedAt INTEGER
                );

                CREATE TABLE Photo (
                    id TEXT PRIMARY KEY,
                    sessionId TEXT NOT NULL REFERENCES Session(id) ON DELETE CASCADE,
                    fileName TEXT NOT NULL,
                    thumbnailFileName TEXT,
                    kind TEXT NOT NULL CHECK (kind IN ('photo')),
                    capturedAt INTEGER NOT NULL,
                    lat REAL,
                    lon REAL,
                    horizontalAccuracy REAL,
                    placeName TEXT,
                    exifJson TEXT,
                    note TEXT,
                    deletedAt INTEGER
                );

                CREATE INDEX idx_Photo_sessionId ON Photo(sessionId);
                CREATE INDEX idx_Photo_capturedAt ON Photo(capturedAt DESC);
                CREATE INDEX idx_Photo_deletedAt ON Photo(deletedAt);
                CREATE INDEX idx_Session_createdAt ON Session(createdAt DESC);
                """)
        }

        return migrator
    }
}
