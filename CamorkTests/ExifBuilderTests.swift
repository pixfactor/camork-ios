import Testing
import Foundation
import ImageIO
@testable import Camork

@Suite("ExifBuilder")
struct ExifBuilderTests {

    @Test("EXIF/TIFF 전체 필드 추출 — iso/shutterSpeed/aperture/focalLength/deviceModel/osVersion")
    func extractsAllFields() {
        let metadata: [String: Any] = [
            kCGImagePropertyExifDictionary as String: [
                kCGImagePropertyExifISOSpeedRatings as String: [400],
                kCGImagePropertyExifExposureTime as String: 0.008,
                kCGImagePropertyExifFNumber as String: 1.8,
                kCGImagePropertyExifFocalLength as String: 5.7,
            ],
            kCGImagePropertyTIFFDictionary as String: [
                kCGImagePropertyTIFFModel as String: "iPhone 17 Pro",
                kCGImagePropertyTIFFSoftware as String: "17.0",
            ],
        ]
        let exif = ExifBuilder.build(from: metadata)
        #expect(exif.iso == 400)
        #expect(exif.shutterSpeed == 0.008)
        #expect(exif.aperture == 1.8)
        #expect(exif.focalLength == 5.7)
        #expect(exif.deviceModel == "iPhone 17 Pro")
        #expect(exif.osVersion == "17.0")
    }

    @Test("metadata 완전 누락 — 모든 필드 nil 유지 (silent 0/empty 금지)")
    func allMissingPreserveNil() {
        let exif = ExifBuilder.build(from: [:])
        #expect(exif.iso == nil)
        #expect(exif.shutterSpeed == nil)
        #expect(exif.aperture == nil)
        #expect(exif.focalLength == nil)
        #expect(exif.deviceModel == nil)
        #expect(exif.osVersion == nil)
    }

    @Test("부분 누락 — ISO만 있을 때 그 외 nil")
    func partialFieldsPreserveNil() {
        let metadata: [String: Any] = [
            kCGImagePropertyExifDictionary as String: [
                kCGImagePropertyExifISOSpeedRatings as String: [100],
            ],
        ]
        let exif = ExifBuilder.build(from: metadata)
        #expect(exif.iso == 100)
        #expect(exif.shutterSpeed == nil)
        #expect(exif.aperture == nil)
        #expect(exif.focalLength == nil)
        #expect(exif.deviceModel == nil)
        #expect(exif.osVersion == nil)
    }

    @Test("ISO 배열 비어있으면 nil")
    func emptyIsoArrayYieldsNil() {
        let metadata: [String: Any] = [
            kCGImagePropertyExifDictionary as String: [
                kCGImagePropertyExifISOSpeedRatings as String: [Int](),
            ],
        ]
        let exif = ExifBuilder.build(from: metadata)
        #expect(exif.iso == nil)
    }
}
