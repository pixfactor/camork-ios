import CloudKit
import Foundation
import Testing
@testable import Camork

@Suite("CloudRecordMapper")
struct CloudRecordMapperTests {
    @Test("Session round trip preserves metadata and first location")
    func sessionRoundTrip() throws {
        let id = UUID()
        let location = LocationSnapshot(
            latitude: 37.5665,
            longitude: 126.9780,
            horizontalAccuracy: 12,
            placeName: "서울시청"
        )
        let session = Session(
            id: id,
            name: "현장 A",
            note: "메모",
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            endedAt: Date(timeIntervalSince1970: 1_800_000_120),
            firstLocation: location,
            deletedAt: nil
        )

        let record = CloudRecordMapper.sessionRecord(from: session)
        let decoded = try CloudRecordMapper.session(from: record)

        #expect(decoded.id == session.id)
        #expect(decoded.name == session.name)
        #expect(decoded.note == session.note)
        #expect(decoded.createdAt == session.createdAt)
        #expect(decoded.endedAt == session.endedAt)
        #expect(decoded.firstLocation == session.firstLocation)
    }

    @Test("Photo round trip preserves canonical media metadata")
    func photoRoundTrip() throws {
        let id = UUID()
        let sessionId = UUID()
        let location = LocationSnapshot(
            latitude: 35.1796,
            longitude: 129.0756,
            horizontalAccuracy: 8,
            placeName: "부산"
        )
        let photo = Photo(
            id: id,
            sessionId: sessionId,
            fileName: "\(id.uuidString).heic",
            kind: .photo,
            capturedAt: Date(timeIntervalSince1970: 1_800_001_000),
            location: location,
            exif: ExifData(
                iso: 200,
                shutterSpeed: 0.01,
                aperture: 1.8,
                focalLength: 24,
                deviceModel: "iPhone",
                osVersion: "26.5"
            ),
            note: "사진 메모",
            deletedAt: Date(timeIntervalSince1970: 1_800_002_000)
        )

        let record = try CloudRecordMapper.photoRecord(from: photo, originalAssetURL: nil)
        let decoded = try CloudRecordMapper.photo(from: record)

        #expect(decoded.id == photo.id)
        #expect(decoded.sessionId == photo.sessionId)
        #expect(decoded.fileName == photo.fileName)
        #expect(decoded.kind == photo.kind)
        #expect(decoded.capturedAt == photo.capturedAt)
        #expect(decoded.location == photo.location)
        #expect(decoded.exif == photo.exif)
        #expect(decoded.note == photo.note)
        #expect(decoded.deletedAt == photo.deletedAt)
    }

    @Test("Photo mapper rejects non-canonical file names before CloudKit upload")
    func rejectsInvalidPhotoFileName() throws {
        let photo = Photo(
            id: UUID(),
            sessionId: UUID(),
            fileName: "../escape.heic",
            kind: .photo,
            capturedAt: Date(timeIntervalSince1970: 1)
        )

        #expect(throws: CloudRecordMapper.Error.invalidFileName) {
            _ = try CloudRecordMapper.photoRecord(from: photo, originalAssetURL: nil)
        }
    }
}
