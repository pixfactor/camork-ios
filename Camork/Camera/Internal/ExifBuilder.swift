import AVFoundation
import Foundation
import ImageIO

/// AVCapturePhoto metadata에서 `ExifData` 추출. 핵심은 단위 테스트 가능한
/// `build(from metadata:)` — 실제 `AVCapturePhoto` 없이 dict 합성으로 동작 검증.
/// `build(from photo:)`는 thin wrapper로 production에서 사용.
///
/// 모든 필드 옵셔널 — metadata에 키가 없거나 타입이 어긋나면 nil 유지 (silent
/// 0/empty 금지, ADR #11).
enum ExifBuilder {
    static func build(from metadata: [String: Any]) -> ExifData {
        let exif = metadata[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let tiff = metadata[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]

        let isoArray = exif[kCGImagePropertyExifISOSpeedRatings as String] as? [NSNumber]
        let iso = isoArray?.first?.intValue

        let shutterSpeed = (exif[kCGImagePropertyExifExposureTime as String] as? NSNumber)?.doubleValue
        let aperture = (exif[kCGImagePropertyExifFNumber as String] as? NSNumber)?.doubleValue
        let focalLength = (exif[kCGImagePropertyExifFocalLength as String] as? NSNumber)?.doubleValue

        let deviceModel = tiff[kCGImagePropertyTIFFModel as String] as? String
        let osVersion = tiff[kCGImagePropertyTIFFSoftware as String] as? String

        return ExifData(
            iso: iso,
            shutterSpeed: shutterSpeed,
            aperture: aperture,
            focalLength: focalLength,
            deviceModel: deviceModel,
            osVersion: osVersion
        )
    }

    static func build(from photo: AVCapturePhoto) -> ExifData {
        build(from: photo.metadata)
    }
}
