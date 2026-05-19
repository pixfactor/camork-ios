import Foundation

/// 미디어 종류. v1 Core는 photo only.
///
/// schema CHECK 제약 `kind IN ('photo')`과 raw value를 일치시켜 silent drift를 막는다.
/// v1.2에서 video를 추가할 때는 migration v3 + 본 enum case 동시 변경.
enum MediaKind: String, Codable, Sendable {
    case photo
}
