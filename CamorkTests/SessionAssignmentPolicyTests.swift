import Testing
import Foundation
@testable import Camork

@Suite("SessionAssignmentPolicy")
struct SessionAssignmentPolicyTests {
    let policy = SessionAssignmentPolicy()

    // MARK: - 6 edge cases

    @Test("case a: GPS latency — current location nil이면 거리 규칙 skip, 시간 규칙만 적용")
    func caseA_gpsLatency() {
        let prevSessionId = UUID()
        let previous = makePhoto(
            sessionId: prevSessionId,
            at: Date(timeIntervalSince1970: 0),
            location: snap(lat: 0, lon: 0, acc: 10)
        )
        let current = makePayload(at: Date(timeIntervalSince1970: 60), location: nil)
        let result = policy.decideSession(previous: previous, current: current, manualFlag: false)
        #expect(result == .continueSession(sessionId: prevSessionId))
    }

    @Test("case b: 위치 권한 거부 — previous/current 모두 location nil, 시간 규칙만 적용")
    func caseB_locationDenied() {
        let prevSessionId = UUID()
        let previous = makePhoto(
            sessionId: prevSessionId,
            at: Date(timeIntervalSince1970: 0),
            location: nil
        )
        let current = makePayload(at: Date(timeIntervalSince1970: 60), location: nil)
        let result = policy.decideSession(previous: previous, current: current, manualFlag: false)
        #expect(result == .continueSession(sessionId: prevSessionId))
    }

    @Test("case c: 첫 촬영 — previous nil → 새 세션")
    func caseC_firstCapture() {
        let result = policy.decideSession(
            previous: nil,
            current: makePayload(at: Date(timeIntervalSince1970: 0), location: nil),
            manualFlag: false
        )
        #expect(result == .newSession)
    }

    @Test("case d: manualFlag true — 같은 자리/직전이어도 새 세션 (GPS/시간 무시)")
    func caseD_manualFlag() {
        let previous = makePhoto(
            at: Date(timeIntervalSince1970: 0),
            location: snap(lat: 0, lon: 0, acc: 5)
        )
        let current = makePayload(
            at: Date(timeIntervalSince1970: 1),
            location: snap(lat: 0, lon: 0, acc: 5)
        )
        let result = policy.decideSession(previous: previous, current: current, manualFlag: true)
        #expect(result == .newSession)
    }

    @Test("case e: 30분 초과 무촬영 — 같은 자리여도 새 세션")
    func caseE_thirtyMinutes() {
        let previous = makePhoto(
            at: Date(timeIntervalSince1970: 0),
            location: snap(lat: 0, lon: 0, acc: 5)
        )
        let current = makePayload(
            at: Date(timeIntervalSince1970: 30 * 60 + 1),
            location: snap(lat: 0, lon: 0, acc: 5)
        )
        let result = policy.decideSession(previous: previous, current: current, manualFlag: false)
        #expect(result == .newSession)
    }

    @Test("case f: manualFlag + 50m 이상 이동 + 30분 경과 — 새 세션 1개만 (중복 newSession 없음)")
    func caseF_combined() {
        let previous = makePhoto(
            at: Date(timeIntervalSince1970: 0),
            location: snap(lat: 0, lon: 0, acc: 5)
        )
        let current = makePayload(
            at: Date(timeIntervalSince1970: 31 * 60),
            location: snap(lat: latOffset(forMeters: 60), lon: 0, acc: 5)
        )
        let result = policy.decideSession(previous: previous, current: current, manualFlag: true)
        #expect(result == .newSession)
    }

    // MARK: - Boundaries

    @Test("거리 boundary: 49m → continue, 50m+ε → new, 51m → new")
    func distanceBoundary() {
        let prevSessionId = UUID()
        let previous = makePhoto(
            sessionId: prevSessionId,
            at: Date(timeIntervalSince1970: 0),
            location: snap(lat: 0, lon: 0, acc: 5)
        )
        // 50.0m exact는 haversine FP rounding (~3 ULP)으로 비결정적 → 50.001m로
        // 명확한 boundary 통과를 검증. 의도: "임계값 이상 → 새 세션".
        let cases: [(Double, SessionAssignmentPolicy.Decision)] = [
            (49.0, .continueSession(sessionId: prevSessionId)),
            (50.001, .newSession),
            (51.0, .newSession),
        ]
        for (meters, expected) in cases {
            let current = makePayload(
                at: Date(timeIntervalSince1970: 60),
                location: snap(lat: latOffset(forMeters: meters), lon: 0, acc: 5)
            )
            let result = policy.decideSession(previous: previous, current: current, manualFlag: false)
            #expect(result == expected, "meters=\(meters)")
        }
    }

    @Test("시간 boundary: 29분 → continue, 30분 → new, 31분 → new")
    func timeBoundary() {
        let prevSessionId = UUID()
        let previous = makePhoto(
            sessionId: prevSessionId,
            at: Date(timeIntervalSince1970: 0),
            location: nil
        )
        let cases: [(Double, SessionAssignmentPolicy.Decision)] = [
            (29.0, .continueSession(sessionId: prevSessionId)),
            (30.0, .newSession),
            (31.0, .newSession),
        ]
        for (minutes, expected) in cases {
            let current = makePayload(
                at: Date(timeIntervalSince1970: minutes * 60),
                location: nil
            )
            let result = policy.decideSession(previous: previous, current: current, manualFlag: false)
            #expect(result == expected, "minutes=\(minutes)")
        }
    }

    @Test("accuracy boundary: 25m/30m → 거리 규칙 적용, 35m → skip")
    func accuracyBoundary() {
        let prevSessionId = UUID()

        for acc in [25.0, 30.0] {
            let previous = makePhoto(
                sessionId: prevSessionId,
                at: Date(timeIntervalSince1970: 0),
                location: snap(lat: 0, lon: 0, acc: acc)
            )
            // 60m 이동 + 1분 — 거리 규칙 적용되면 new, skip되면 시간 규칙(<30min)으로 continue
            let current = makePayload(
                at: Date(timeIntervalSince1970: 60),
                location: snap(lat: latOffset(forMeters: 60), lon: 0, acc: acc)
            )
            let result = policy.decideSession(previous: previous, current: current, manualFlag: false)
            #expect(result == .newSession, "acc=\(acc) — 거리 규칙 적용되어야 함")
        }

        // acc=35 → 거리 규칙 skip → 1분 < 30분 → continue
        let previous35 = makePhoto(
            sessionId: prevSessionId,
            at: Date(timeIntervalSince1970: 0),
            location: snap(lat: 0, lon: 0, acc: 35)
        )
        let current35 = makePayload(
            at: Date(timeIntervalSince1970: 60),
            location: snap(lat: latOffset(forMeters: 60), lon: 0, acc: 35)
        )
        let result35 = policy.decideSession(previous: previous35, current: current35, manualFlag: false)
        #expect(result35 == .continueSession(sessionId: prevSessionId), "acc=35 — 거리 규칙 skip")
    }

    @Test("horizontalAccuracy 음수(-1: CoreLocation no-fix sentinel) — 거리 규칙 skip, 시간 규칙으로 fallback")
    func accuracyNil() {
        let prevSessionId = UUID()
        let previous = makePhoto(
            sessionId: prevSessionId,
            at: Date(timeIntervalSince1970: 0),
            location: snap(lat: 0, lon: 0, acc: -1)
        )
        // 60m 이동했지만 acc=-1 → 거리 규칙 skip → 1분 < 30분 → continue
        let current = makePayload(
            at: Date(timeIntervalSince1970: 60),
            location: snap(lat: latOffset(forMeters: 60), lon: 0, acc: -1)
        )
        let result = policy.decideSession(previous: previous, current: current, manualFlag: false)
        #expect(result == .continueSession(sessionId: prevSessionId))
    }
}

// MARK: - Helpers

private func makePhoto(
    id: UUID = UUID(),
    sessionId: UUID = UUID(),
    at capturedAt: Date,
    location: LocationSnapshot?
) -> Photo {
    Photo(
        id: id,
        sessionId: sessionId,
        fileName: "test.heic",
        kind: .photo,
        capturedAt: capturedAt,
        location: location
    )
}

private func makePayload(at capturedAt: Date, location: LocationSnapshot?) -> PhotoCapturePayload {
    PhotoCapturePayload(
        data: Data(),
        capturedAt: capturedAt,
        location: location,
        exif: nil
    )
}

private func snap(lat: Double, lon: Double, acc: Double, placeName: String? = nil) -> LocationSnapshot {
    LocationSnapshot(
        latitude: lat,
        longitude: lon,
        horizontalAccuracy: acc,
        placeName: placeName
    )
}

/// 위도 1° ≈ R·π/180 meter. 순수 위도 변위에 대한 정확한 degree offset.
private func latOffset(forMeters m: Double) -> Double {
    m / (6_371_000.0 * Double.pi / 180.0)
}
