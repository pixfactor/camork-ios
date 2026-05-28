import CloudKit
import Foundation

enum CloudRecordMapper {
    enum RecordType {
        static let session = "CamorkSession"
        static let photo = "CamorkPhoto"
    }

    enum SessionField {
        static let name = "name"
        static let note = "note"
        static let createdAt = "createdAt"
        static let endedAt = "endedAt"
        static let firstLat = "firstLat"
        static let firstLon = "firstLon"
        static let firstHorizontalAccuracy = "firstHorizontalAccuracy"
        static let firstPlaceName = "firstPlaceName"
        static let deletedAt = "deletedAt"
    }

    enum PhotoField {
        static let sessionId = "sessionId"
        static let fileName = "fileName"
        static let kind = "kind"
        static let capturedAt = "capturedAt"
        static let lat = "lat"
        static let lon = "lon"
        static let horizontalAccuracy = "horizontalAccuracy"
        static let placeName = "placeName"
        static let exifJson = "exifJson"
        static let note = "note"
        static let deletedAt = "deletedAt"
        static let originalAsset = "originalAsset"
    }

    enum Error: Swift.Error, Sendable, Equatable {
        case invalidRecordType(expected: String, actual: String)
        case invalidUUID(field: String)
        case missingField(String)
        case invalidMediaKind
        case invalidFileName
        case invalidExif
    }

    static func sessionRecord(from session: Session) -> CKRecord {
        let record = CKRecord(
            recordType: RecordType.session,
            recordID: CKRecord.ID(recordName: session.id.uuidString)
        )
        apply(session, to: record)
        return record
    }

    static func apply(_ session: Session, to record: CKRecord) {
        record[SessionField.name] = session.name as NSString
        setOptionalString(session.note, for: SessionField.note, on: record)
        record[SessionField.createdAt] = session.createdAt as NSDate
        setOptionalDate(session.endedAt, for: SessionField.endedAt, on: record)
        setLocation(session.firstLocation, prefix: "first", on: record)
        setOptionalDate(session.deletedAt, for: SessionField.deletedAt, on: record)
    }

    static func session(from record: CKRecord) throws -> Session {
        guard record.recordType == RecordType.session else {
            throw Error.invalidRecordType(expected: RecordType.session, actual: record.recordType)
        }
        guard let id = UUID(uuidString: record.recordID.recordName) else {
            throw Error.invalidUUID(field: "recordName")
        }
        let location = location(
            lat: record[SessionField.firstLat] as? Double,
            lon: record[SessionField.firstLon] as? Double,
            accuracy: record[SessionField.firstHorizontalAccuracy] as? Double,
            placeName: record[SessionField.firstPlaceName] as? String
        )
        return Session(
            id: id,
            name: try requiredString(SessionField.name, from: record),
            note: record[SessionField.note] as? String,
            createdAt: try requiredDate(SessionField.createdAt, from: record),
            endedAt: record[SessionField.endedAt] as? Date,
            firstLocation: location,
            deletedAt: record[SessionField.deletedAt] as? Date
        )
    }

    static func photoRecord(from photo: Photo, originalAssetURL: URL?) throws -> CKRecord {
        let record = CKRecord(
            recordType: RecordType.photo,
            recordID: CKRecord.ID(recordName: photo.id.uuidString)
        )
        try apply(photo, originalAssetURL: originalAssetURL, to: record)
        return record
    }

    static func apply(_ photo: Photo, originalAssetURL: URL?, to record: CKRecord) throws {
        guard photo.fileName == "\(photo.id.uuidString).heic" else {
            throw Error.invalidFileName
        }
        record[PhotoField.sessionId] = photo.sessionId.uuidString as NSString
        record[PhotoField.fileName] = photo.fileName as NSString
        record[PhotoField.kind] = photo.kind.rawValue as NSString
        record[PhotoField.capturedAt] = photo.capturedAt as NSDate
        setLocation(photo.location, prefix: nil, on: record)
        if let exif = photo.exif {
            guard let json = String(data: try JSONEncoder().encode(exif), encoding: .utf8) else {
                throw Error.invalidExif
            }
            record[PhotoField.exifJson] = json as NSString
        } else {
            record[PhotoField.exifJson] = nil
        }
        setOptionalString(photo.note, for: PhotoField.note, on: record)
        setOptionalDate(photo.deletedAt, for: PhotoField.deletedAt, on: record)
        if let originalAssetURL {
            record[PhotoField.originalAsset] = CKAsset(fileURL: originalAssetURL)
        }
    }

    static func photo(from record: CKRecord) throws -> Photo {
        guard record.recordType == RecordType.photo else {
            throw Error.invalidRecordType(expected: RecordType.photo, actual: record.recordType)
        }
        guard let id = UUID(uuidString: record.recordID.recordName) else {
            throw Error.invalidUUID(field: "recordName")
        }
        guard let sessionId = UUID(uuidString: try requiredString(PhotoField.sessionId, from: record)) else {
            throw Error.invalidUUID(field: PhotoField.sessionId)
        }
        guard let kind = MediaKind(rawValue: try requiredString(PhotoField.kind, from: record)) else {
            throw Error.invalidMediaKind
        }
        let fileName = try requiredString(PhotoField.fileName, from: record)
        guard fileName == "\(id.uuidString).heic" else {
            throw Error.invalidFileName
        }
        let exif: ExifData?
        if let json = record[PhotoField.exifJson] as? String {
            exif = try JSONDecoder().decode(ExifData.self, from: Data(json.utf8))
        } else {
            exif = nil
        }
        return Photo(
            id: id,
            sessionId: sessionId,
            fileName: fileName,
            kind: kind,
            capturedAt: try requiredDate(PhotoField.capturedAt, from: record),
            location: location(
                lat: record[PhotoField.lat] as? Double,
                lon: record[PhotoField.lon] as? Double,
                accuracy: record[PhotoField.horizontalAccuracy] as? Double,
                placeName: record[PhotoField.placeName] as? String
            ),
            exif: exif,
            note: record[PhotoField.note] as? String,
            deletedAt: record[PhotoField.deletedAt] as? Date
        )
    }

    static func originalAssetURL(from record: CKRecord) -> URL? {
        (record[PhotoField.originalAsset] as? CKAsset)?.fileURL
    }

    private static func requiredString(_ field: String, from record: CKRecord) throws -> String {
        guard let value = record[field] as? String, !value.isEmpty else {
            throw Error.missingField(field)
        }
        return value
    }

    private static func requiredDate(_ field: String, from record: CKRecord) throws -> Date {
        guard let value = record[field] as? Date else {
            throw Error.missingField(field)
        }
        return value
    }

    private static func setOptionalString(_ value: String?, for field: String, on record: CKRecord) {
        if let value {
            record[field] = value as NSString
        } else {
            record[field] = nil
        }
    }

    private static func setOptionalDate(_ value: Date?, for field: String, on record: CKRecord) {
        if let value {
            record[field] = value as NSDate
        } else {
            record[field] = nil
        }
    }

    private static func setLocation(_ value: LocationSnapshot?, prefix: String?, on record: CKRecord) {
        let latField = prefix.map { "\($0)Lat" } ?? PhotoField.lat
        let lonField = prefix.map { "\($0)Lon" } ?? PhotoField.lon
        let accuracyField = prefix.map { "\($0)HorizontalAccuracy" } ?? PhotoField.horizontalAccuracy
        let placeField = prefix.map { "\($0)PlaceName" } ?? PhotoField.placeName
        setOptionalDouble(value?.latitude, for: latField, on: record)
        setOptionalDouble(value?.longitude, for: lonField, on: record)
        setOptionalDouble(value?.horizontalAccuracy, for: accuracyField, on: record)
        setOptionalString(value?.placeName, for: placeField, on: record)
    }

    private static func setOptionalDouble(_ value: Double?, for field: String, on record: CKRecord) {
        if let value {
            record[field] = NSNumber(value: value)
        } else {
            record[field] = nil
        }
    }

    private static func location(
        lat: Double?,
        lon: Double?,
        accuracy: Double?,
        placeName: String?
    ) -> LocationSnapshot? {
        guard let lat, let lon else { return nil }
        return LocationSnapshot(
            latitude: lat,
            longitude: lon,
            horizontalAccuracy: accuracy ?? -1,
            placeName: placeName
        )
    }
}
