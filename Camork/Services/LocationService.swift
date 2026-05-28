import CoreLocation
import Foundation

enum LocationPlaceNameFormatter {
    static func displayName(
        name: String?,
        thoroughfare: String?,
        locality: String?,
        administrativeArea: String?,
        country: String?
    ) -> String? {
        let candidates = [
            compact([locality, thoroughfare]),
            compact([administrativeArea, locality]),
            name,
            locality,
            administrativeArea,
            country
        ]

        return candidates
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    static func displayName(from placemark: CLPlacemark) -> String? {
        displayName(
            name: placemark.name,
            thoroughfare: placemark.thoroughfare,
            locality: placemark.locality,
            administrativeArea: placemark.administrativeArea,
            country: placemark.country
        )
    }

    private static func compact(_ parts: [String?]) -> String? {
        let joined = parts
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return joined.isEmpty ? nil : joined
    }
}

/// CoreLocation snapshot 제공자. AVFoundation callback queue(`@Sendable` closure 외부)
/// 에서 `latestKnown()`이 **synchronously** 호출 가능해야 하므로 actor 대신 NSLock 기반
/// thread-safe final class + `@unchecked Sendable` 채택 (설계 결정 — ADR #6
/// "LocationService.latestKnown() sync snapshot").
///
/// 책임 경계:
/// - 권한 prompt는 본 클래스 책임 외 (`PermissionsService` 소유).
/// - 본 클래스는 권한 status snapshot + 위치 업데이트 ingestion만.
/// - `latestKnown()`은 권한이 denied/restricted/notDetermined이거나 ingestion이 한
///   번도 없으면 nil (silent stale 반환 금지).
final class LocationService: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var _lastLocation: LocationSnapshot?
    private var _authStatus: CLAuthorizationStatus
    private let manager: CLLocationManager?

    /// Production: 실제 CLLocationManager 생성 + delegate 등록 + initial auth status snapshot.
    override convenience init() {
        let m = CLLocationManager()
        let initial = m.authorizationStatus
        self.init(manager: m, initialStatus: initial)
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyBest
    }

    /// Test seam: nil manager로 인스턴스화하면 startUpdates/stopUpdates가 no-op이 되어
    /// 시뮬레이터 권한 prompt를 회피. tests는 `ingest` / `updateAuthorizationStatus`로
    /// 외부 입력을 직접 시뮬레이션.
    init(manager: CLLocationManager?, initialStatus: CLAuthorizationStatus) {
        self.manager = manager
        self._authStatus = initialStatus
        super.init()
    }

    // MARK: - Public API

    /// AVFoundation callback queue에서 sync 호출. lock으로 thread-safe.
    func latestKnown() -> LocationSnapshot? {
        lock.lock(); defer { lock.unlock() }
        guard Self.isAuthorizationGranted(_authStatus) else { return nil }
        return _lastLocation
    }

    func startUpdates() {
        manager?.startUpdatingLocation()
    }

    func stopUpdates() {
        manager?.stopUpdatingLocation()
    }

    /// Capture-save 직전에 호출하는 best-effort reverse geocoding. 실패하거나 결과가
    /// 비어 있으면 원본 snapshot을 그대로 반환해 촬영 저장 경로를 막지 않는다.
    func reverseGeocode(_ snapshot: LocationSnapshot) async -> LocationSnapshot {
        guard snapshot.placeName?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty != false else {
            return snapshot
        }

        let location = CLLocation(
            latitude: snapshot.latitude,
            longitude: snapshot.longitude
        )

        return await withCheckedContinuation { continuation in
            CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
                let placeName = placemarks?
                    .compactMap(LocationPlaceNameFormatter.displayName(from:))
                    .first
                continuation.resume(returning: snapshot.withPlaceName(placeName))
            }
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        updateAuthorizationStatus(manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let cl = locations.last else { return }
        ingest(cl)
    }

    // MARK: - Internal mutation (test seam — @testable import으로 접근)

    func updateAuthorizationStatus(_ status: CLAuthorizationStatus) {
        lock.lock()
        _authStatus = status
        lock.unlock()
    }

    /// 음수 accuracy(no fix)는 silent ignore — 마지막 유효 snapshot을 보존.
    func ingest(_ location: CLLocation) {
        guard let snapshot = Self.makeSnapshot(from: location) else { return }
        lock.lock()
        _lastLocation = snapshot
        lock.unlock()
    }

    // MARK: - Pure conversion (unit-testable, static)

    static func makeSnapshot(from location: CLLocation) -> LocationSnapshot? {
        guard location.horizontalAccuracy >= 0 else { return nil }
        return LocationSnapshot(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude,
            horizontalAccuracy: location.horizontalAccuracy,
            placeName: nil
        )
    }

    static func isAuthorizationGranted(_ status: CLAuthorizationStatus) -> Bool {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: return true
        default: return false
        }
    }
}
