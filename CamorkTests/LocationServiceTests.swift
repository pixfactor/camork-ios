import Testing
import CoreLocation
@testable import Camork

@Suite("LocationService")
struct LocationServiceTests {

    // MARK: - Pure conversion (makeSnapshot)

    @Test("makeSnapshot: horizontalAccuracy 음수(no fix) → nil 반환")
    func makeSnapshotNegativeAccuracyYieldsNil() {
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.5, longitude: 127.0),
            altitude: 0,
            horizontalAccuracy: -1,
            verticalAccuracy: -1,
            timestamp: Date()
        )
        #expect(LocationService.makeSnapshot(from: location) == nil)
    }

    @Test("makeSnapshot: 유효한 accuracy → LocationSnapshot으로 변환 (placeName은 nil)")
    func makeSnapshotValid() {
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.5, longitude: 127.0),
            altitude: 0,
            horizontalAccuracy: 10,
            verticalAccuracy: -1,
            timestamp: Date()
        )
        let snapshot = LocationService.makeSnapshot(from: location)
        #expect(snapshot != nil)
        #expect(snapshot?.latitude == 37.5)
        #expect(snapshot?.longitude == 127.0)
        #expect(snapshot?.horizontalAccuracy == 10)
        #expect(snapshot?.placeName == nil)
    }

    // MARK: - latestKnown gated by authorization

    @Test("latestKnown: status=.denied → ingested 후에도 nil")
    func latestKnownDeniedReturnsNil() {
        let service = LocationService(manager: nil, initialStatus: .denied)
        service.ingest(validLocation())
        #expect(service.latestKnown() == nil)
    }

    @Test("latestKnown: status=.notDetermined → nil")
    func latestKnownNotDeterminedReturnsNil() {
        let service = LocationService(manager: nil, initialStatus: .notDetermined)
        service.ingest(validLocation())
        #expect(service.latestKnown() == nil)
    }

    @Test("latestKnown: status=.restricted → nil")
    func latestKnownRestrictedReturnsNil() {
        let service = LocationService(manager: nil, initialStatus: .restricted)
        service.ingest(validLocation())
        #expect(service.latestKnown() == nil)
    }

    @Test("latestKnown: status=.authorizedWhenInUse + 유효 ingestion → 해당 snapshot 반환")
    func latestKnownWhenInUseReturnsSnapshot() {
        let service = LocationService(manager: nil, initialStatus: .authorizedWhenInUse)
        service.ingest(validLocation(lat: 37.5, lon: 127.0, acc: 10))
        let snap = service.latestKnown()
        #expect(snap?.latitude == 37.5)
        #expect(snap?.longitude == 127.0)
        #expect(snap?.horizontalAccuracy == 10)
    }

    @Test("latestKnown: status=.authorizedAlways도 granted 매핑 (이론적 상황 대비)")
    func latestKnownAlwaysReturnsSnapshot() {
        let service = LocationService(manager: nil, initialStatus: .authorizedAlways)
        service.ingest(validLocation(lat: 35.0, lon: 128.0, acc: 5))
        #expect(service.latestKnown()?.latitude == 35.0)
    }

    @Test("latestKnown: authorized이지만 ingestion 한 번도 없으면 nil")
    func latestKnownNoIngestionReturnsNil() {
        let service = LocationService(manager: nil, initialStatus: .authorizedWhenInUse)
        #expect(service.latestKnown() == nil)
    }

    // MARK: - Ingest invariants

    @Test("ingest 음수 accuracy → 마지막 유효 snapshot을 덮지 않음 (no-op)")
    func ingestNegativeAccuracyIsNoOp() {
        let service = LocationService(manager: nil, initialStatus: .authorizedWhenInUse)
        service.ingest(validLocation(lat: 37.5, lon: 127.0, acc: 10))
        service.ingest(CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            altitude: 0,
            horizontalAccuracy: -1,
            verticalAccuracy: -1,
            timestamp: Date()
        ))
        let snap = service.latestKnown()
        #expect(snap?.latitude == 37.5)
        #expect(snap?.longitude == 127.0)
    }

    // MARK: - Authorization mutation

    @Test("updateAuthorizationStatus: 권한이 revoked되면 ingested snapshot도 즉시 차단")
    func authorizationRevokedBlocksLatestKnown() {
        let service = LocationService(manager: nil, initialStatus: .authorizedWhenInUse)
        service.ingest(validLocation())
        #expect(service.latestKnown() != nil)

        service.updateAuthorizationStatus(.denied)
        #expect(service.latestKnown() == nil)
    }
}

// MARK: - Helpers

private func validLocation(lat: Double = 37.5, lon: Double = 127.0, acc: Double = 10) -> CLLocation {
    CLLocation(
        coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
        altitude: 0,
        horizontalAccuracy: acc,
        verticalAccuracy: -1,
        timestamp: Date()
    )
}
