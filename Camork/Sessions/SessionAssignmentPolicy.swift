import Foundation

/// 자동 세션 묶음 정책. pure struct — actor/DB/instance state 의존 없음 (ADR #4).
///
/// 결정 순서:
/// 1. `manualFlag == true` → newSession (override-all)
/// 2. `previous == nil` (첫 촬영) → newSession
/// 3. 거리 규칙: previous/current 모두 location 있고 horizontalAccuracy `0...30`
///    범위(0 포함 = 완벽 정확도, 음수 = CoreLocation no-fix sentinel은 제외)일 때만
///    haversine distance ≥ 50m → newSession
/// 4. 시간 규칙: elapsed ≥ 30분 → newSession
/// 5. 그 외 → continueSession(previous.sessionId)
struct SessionAssignmentPolicy: Sendable {
    enum Decision: Equatable, Sendable {
        case newSession
        case continueSession(sessionId: UUID)
    }

    init() {}

    func decideSession(
        previous: Photo?,
        current: PhotoCapturePayload,
        manualFlag: Bool
    ) -> Decision {
        if manualFlag { return .newSession }
        guard let previous else { return .newSession }

        if let prevLoc = previous.location,
           let currLoc = current.location,
           (0...30).contains(prevLoc.horizontalAccuracy),
           (0...30).contains(currLoc.horizontalAccuracy) {
            if haversineDistance(prevLoc, currLoc) >= 50 {
                return .newSession
            }
        }

        let elapsed = current.capturedAt.timeIntervalSince(previous.capturedAt)
        if elapsed >= 30 * 60 {
            return .newSession
        }

        return .continueSession(sessionId: previous.sessionId)
    }
}

private func haversineDistance(_ a: LocationSnapshot, _ b: LocationSnapshot) -> Double {
    let R = 6_371_000.0
    let phi1 = a.latitude * .pi / 180
    let phi2 = b.latitude * .pi / 180
    let dPhi = (b.latitude - a.latitude) * .pi / 180
    let dLambda = (b.longitude - a.longitude) * .pi / 180
    let h = sin(dPhi / 2) * sin(dPhi / 2)
        + cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2)
    let c = 2 * atan2(sqrt(h), sqrt(1 - h))
    return R * c
}
