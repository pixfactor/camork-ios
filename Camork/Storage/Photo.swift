import Foundation
import GRDB

/// Photo row. v1 Core는 photo only (`MediaKind.photo`).
///
/// **Date codec (ADR #11 + v1.2 C1)**: `capturedAt`/`deletedAt`는 SQLite INTEGER에
/// Unix epoch seconds (`Int64`)로 명시 매핑. GRDB의 silent
/// `Date.timeIntervalSinceReferenceDate` 또는 ISO 8601 매핑을 피한다.
///
/// **UUID / MediaKind validate (v1.2 C2)**: corrupt row를 silent mint하지 않고
/// `PhotoDecodingError`로 throw. 외부 도구로 DB가 수정되어 CHECK 제약이 우회되더라도
/// 잘못된 사진을 임의 세션에 attach 하지 않는다.
struct Photo: Identifiable, Sendable, FetchableRecord, PersistableRecord {
    let id: UUID
    let sessionId: UUID
    let fileName: String
    let thumbnailFileName: String?
    let kind: MediaKind
    let capturedAt: Date
    let location: LocationSnapshot?
    let exif: ExifData?
    var note: String?
    var deletedAt: Date?

    enum Columns: String, ColumnExpression {
        case id, sessionId, fileName, thumbnailFileName, kind
        case capturedAt, lat, lon, horizontalAccuracy, placeName
        case exifJson, note, deletedAt
    }

    static let databaseTableName = "Photo"

    init(
        id: UUID,
        sessionId: UUID,
        fileName: String,
        thumbnailFileName: String? = nil,
        kind: MediaKind,
        capturedAt: Date,
        location: LocationSnapshot? = nil,
        exif: ExifData? = nil,
        note: String? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.sessionId = sessionId
        self.fileName = fileName
        self.thumbnailFileName = thumbnailFileName
        self.kind = kind
        self.capturedAt = capturedAt
        self.location = location
        self.exif = exif
        self.note = note
        self.deletedAt = deletedAt
    }

    init(row: Row) throws {
        guard let idStr: String = row[Columns.id], let parsedId = UUID(uuidString: idStr) else {
            throw PhotoDecodingError.invalidUUID(column: "id")
        }
        guard let sidStr: String = row[Columns.sessionId], let parsedSid = UUID(uuidString: sidStr) else {
            throw PhotoDecodingError.invalidUUID(column: "sessionId")
        }
        guard let kindStr: String = row[Columns.kind], let parsedKind = MediaKind(rawValue: kindStr) else {
            throw PhotoDecodingError.invalidMediaKind
        }
        self.id = parsedId
        self.sessionId = parsedSid
        self.kind = parsedKind
        self.fileName = row[Columns.fileName]
        self.thumbnailFileName = row[Columns.thumbnailFileName]

        let capturedSeconds: Int64 = row[Columns.capturedAt]
        self.capturedAt = Date(timeIntervalSince1970: TimeInterval(capturedSeconds))

        if let lat: Double = row[Columns.lat], let lon: Double = row[Columns.lon] {
            self.location = LocationSnapshot(
                latitude: lat,
                longitude: lon,
                horizontalAccuracy: row[Columns.horizontalAccuracy] ?? -1,
                placeName: row[Columns.placeName]
            )
        } else {
            self.location = nil
        }

        if let json: String = row[Columns.exifJson] {
            self.exif = try JSONDecoder().decode(ExifData.self, from: Data(json.utf8))
        } else {
            self.exif = nil
        }

        self.note = row[Columns.note]
        if let d: Int64 = row[Columns.deletedAt] {
            self.deletedAt = Date(timeIntervalSince1970: TimeInterval(d))
        } else {
            self.deletedAt = nil
        }
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id.uuidString
        container[Columns.sessionId] = sessionId.uuidString
        container[Columns.fileName] = fileName
        container[Columns.thumbnailFileName] = thumbnailFileName
        container[Columns.kind] = kind.rawValue
        container[Columns.capturedAt] = Int64(capturedAt.timeIntervalSince1970)
        container[Columns.lat] = location?.latitude
        container[Columns.lon] = location?.longitude
        container[Columns.horizontalAccuracy] = location?.horizontalAccuracy
        container[Columns.placeName] = location?.placeName
        if let exif {
            container[Columns.exifJson] = String(data: try JSONEncoder().encode(exif), encoding: .utf8)
        } else {
            container[Columns.exifJson] = nil
        }
        container[Columns.note] = note
        container[Columns.deletedAt] = deletedAt.map { Int64($0.timeIntervalSince1970) }
    }
}

enum PhotoDecodingError: Error, Sendable, Equatable {
    case invalidUUID(column: String)
    case invalidMediaKind
}
