import Foundation

/// 사진 촬영 시점의 위치 스냅샷. Photo / Session 테이블에 embed columns로 풀어 매핑한다.
///
/// `horizontalAccuracy`는 CoreLocation 관례에 따라 음수면 "값 없음/유효하지 않음".
/// DB row에서 `lat`/`lon`이 둘 다 non-nil인 경우에만 인스턴스 생성, 정확도가 nil이면 -1 fallback.
struct LocationSnapshot: Codable, Sendable, Equatable {
    let latitude: Double
    let longitude: Double
    let horizontalAccuracy: Double
    let placeName: String?

    func withPlaceName(_ placeName: String?) -> LocationSnapshot {
        LocationSnapshot(
            latitude: latitude,
            longitude: longitude,
            horizontalAccuracy: horizontalAccuracy,
            placeName: placeName
        )
    }
}
