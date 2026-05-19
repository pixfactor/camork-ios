import AVFoundation
import CoreLocation
import Foundation

/// 카메라 / 위치 권한 상태 (v1 Core). 마이크는 v1 photo-only 정책상 미사용 — 추가하지 않음.
enum PermissionState: Sendable, Equatable {
    case granted
    case denied
    case notDetermined
    case restricted
}

/// AVFoundation / CoreLocation 권한 매핑 + 라이브 쿼리 + async 요청.
///
/// `map` 함수는 pure — system enum → `PermissionState` 변환만 담당. 단위 테스트에서
/// 직접 호출 가능. 라이브 쿼리(`cameraState` / `locationState`)와 요청
/// (`requestCamera` / `requestLocation`)은 system API를 얇게 감싼다.
struct PermissionsService: Sendable {
    init() {}

    // MARK: - Pure mapping (unit-testable)

    static func map(camera status: AVAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: return .granted
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }

    static func map(location status: CLAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse: return .granted
        case .denied: return .denied
        case .notDetermined: return .notDetermined
        case .restricted: return .restricted
        @unknown default: return .denied
        }
    }

    // MARK: - Live query

    func cameraState() -> PermissionState {
        Self.map(camera: AVCaptureDevice.authorizationStatus(for: .video))
    }

    func locationState() -> PermissionState {
        Self.map(location: CLLocationManager().authorizationStatus)
    }

    // MARK: - Request (async)

    func requestCamera() async -> PermissionState {
        _ = await AVCaptureDevice.requestAccess(for: .video)
        return cameraState()
    }

    /// system prompt가 닫힐 때까지 await — delegate callback을 CheckedContinuation으로 awaitable화.
    func requestLocation() async -> PermissionState {
        await LocationAuthorizationRequest.requestWhenInUse()
    }
}

// MARK: - Location request continuation helper

/// CLLocationManager 권한 요청을 async/await 형태로 wrapping. delegate-set 즉시 발생하는
/// 초기 `.notDetermined` 콜백은 무시하고, 실제 사용자 응답 콜백만 continuation을 resume.
private final class LocationAuthorizationRequest: NSObject, CLLocationManagerDelegate, @unchecked Sendable {
    private let manager = CLLocationManager()
    private let lock = NSLock()
    private var continuation: CheckedContinuation<CLAuthorizationStatus, Never>?

    static func requestWhenInUse() async -> PermissionState {
        let request = LocationAuthorizationRequest()
        let status = await request.wait()
        return PermissionsService.map(location: status)
    }

    override init() {
        super.init()
        manager.delegate = self
    }

    private func wait() async -> CLAuthorizationStatus {
        let initial = manager.authorizationStatus
        if initial != .notDetermined {
            return initial
        }
        return await withCheckedContinuation { c in
            lock.lock()
            self.continuation = c
            lock.unlock()
            DispatchQueue.main.async { [weak self] in
                self?.manager.requestWhenInUseAuthorization()
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        guard status != .notDetermined else { return }
        lock.lock()
        let c = continuation
        continuation = nil
        lock.unlock()
        c?.resume(returning: status)
    }
}
