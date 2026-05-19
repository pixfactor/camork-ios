import Foundation
import GRDB

/// Session row. 한 번의 작업 묶음 — 자동 묶임 정책(`SessionAssignmentPolicy`)의 출력.
///
/// **Date codec (ADR #11 + v1.2 C1)**: `createdAt`/`endedAt`/`deletedAt`는 Unix epoch
/// seconds (`Int64`)로 명시 매핑. Photo와 동일 규칙.
///
/// **UUID validate (v1.2 C2)**: 잘못된 UUID 행은 `SessionDecodingError`로 throw.
struct Session: Identifiable, Sendable, FetchableRecord, PersistableRecord {
    let id: UUID
    let name: String
    var note: String?
    let createdAt: Date
    var endedAt: Date?
    let firstLocation: LocationSnapshot?
    var deletedAt: Date?

    enum Columns: String, ColumnExpression {
        case id, name, note, createdAt, endedAt
        case firstLat, firstLon, firstHorizontalAccuracy, firstPlaceName
        case deletedAt
    }

    static let databaseTableName = "Session"

    init(
        id: UUID,
        name: String,
        note: String? = nil,
        createdAt: Date,
        endedAt: Date? = nil,
        firstLocation: LocationSnapshot? = nil,
        deletedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.note = note
        self.createdAt = createdAt
        self.endedAt = endedAt
        self.firstLocation = firstLocation
        self.deletedAt = deletedAt
    }

    init(row: Row) throws {
        guard let idStr: String = row[Columns.id], let parsedId = UUID(uuidString: idStr) else {
            throw SessionDecodingError.invalidUUID(column: "id")
        }
        self.id = parsedId
        self.name = row[Columns.name]
        self.note = row[Columns.note]

        let createdSeconds: Int64 = row[Columns.createdAt]
        self.createdAt = Date(timeIntervalSince1970: TimeInterval(createdSeconds))

        if let e: Int64 = row[Columns.endedAt] {
            self.endedAt = Date(timeIntervalSince1970: TimeInterval(e))
        } else {
            self.endedAt = nil
        }

        if let lat: Double = row[Columns.firstLat], let lon: Double = row[Columns.firstLon] {
            self.firstLocation = LocationSnapshot(
                latitude: lat,
                longitude: lon,
                horizontalAccuracy: row[Columns.firstHorizontalAccuracy] ?? -1,
                placeName: row[Columns.firstPlaceName]
            )
        } else {
            self.firstLocation = nil
        }

        if let d: Int64 = row[Columns.deletedAt] {
            self.deletedAt = Date(timeIntervalSince1970: TimeInterval(d))
        } else {
            self.deletedAt = nil
        }
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id.uuidString
        container[Columns.name] = name
        container[Columns.note] = note
        container[Columns.createdAt] = Int64(createdAt.timeIntervalSince1970)
        container[Columns.endedAt] = endedAt.map { Int64($0.timeIntervalSince1970) }
        container[Columns.firstLat] = firstLocation?.latitude
        container[Columns.firstLon] = firstLocation?.longitude
        container[Columns.firstHorizontalAccuracy] = firstLocation?.horizontalAccuracy
        container[Columns.firstPlaceName] = firstLocation?.placeName
        container[Columns.deletedAt] = deletedAt.map { Int64($0.timeIntervalSince1970) }
    }
}

enum SessionDecodingError: Error, Sendable, Equatable {
    case invalidUUID(column: String)
}
