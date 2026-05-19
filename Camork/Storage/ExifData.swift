import Foundation

/// 촬영 EXIF 메타. JSON blob으로 직렬화해 `Photo.exifJson` 컬럼에 저장.
///
/// v1.1+ 검색에서 EXIF 조건은 비현실적 → 인덱스 불필요 (ADR #11).
/// 모든 필드 optional, 추출 실패 시 nil 그대로 보존 (silent 0으로 채우지 않음).
struct ExifData: Codable, Sendable, Equatable {
    let iso: Int?
    let shutterSpeed: Double?
    let aperture: Double?
    let focalLength: Double?
    let deviceModel: String?
    let osVersion: String?
}
