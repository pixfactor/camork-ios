import Foundation

/// CameraScreen의 view-level 상태 머신. pure value — SwiftUI / AVFoundation 의존 없음.
///
/// 본 enum은 (camera permission × location permission × isPending × isInFlight)
/// 조합을 결정적으로 4개의 분기로 축약한다:
/// - `cameraActive(chip:)`: 권한 OK, 프리뷰 가능. chip 상태는 in-flight/pending 표시.
/// - `permissionDenied(target:)`: 권한 거부/제한 — 사용자가 설정에서 해제해야 함.
/// - `requestPrompt`: notDetermined — 권한 prompt를 띄울 시점.
/// - `cameraInitError(reason:)`: AVFoundation 초기화 실패 — `compute`는 본 케이스를
///   직접 생산하지 않음 (DependencyContainer bootstrap 실패는 `CamorkApp.Bootstrap.failed`
///   가 잡음). 본 케이스는 화면-국소적 에러(예: 라이프사이클 도중 cameraSession 재시도
///   실패)를 표현하기 위해 view-side에서 직접 구성.
enum CameraScreenViewState: Equatable {
    case cameraActive(chip: ChipState)
    case permissionDenied(target: PermissionTarget)
    case requestPrompt
    case cameraInitError(reason: String)

    enum ChipState: Equatable {
        case idle
        case pending
        case disabled
    }

    enum PermissionTarget: Equatable {
        case camera
        case location
    }

    /// Deterministic precedence (camera permission이 location permission보다 우선):
    /// 1. camera == .denied / .restricted → `.permissionDenied(.camera)`
    /// 2. camera == .notDetermined → `.requestPrompt`
    /// 3. (camera granted) location == .denied / .restricted → `.permissionDenied(.location)`
    /// 4. (camera granted) location == .notDetermined → `.requestPrompt`
    /// 5. 둘 다 granted → `.cameraActive(chip:)`
    ///    chip 결정:
    ///    - `isInFlight == true` → `.disabled` (in-flight가 isPending보다 우선)
    ///    - `isPending == true` (in-flight false) → `.pending`
    ///    - else → `.idle`
    static func compute(
        camera: PermissionState,
        location: PermissionState,
        isPending: Bool,
        isInFlight: Bool
    ) -> CameraScreenViewState {
        switch camera {
        case .denied, .restricted:
            return .permissionDenied(target: .camera)
        case .notDetermined:
            return .requestPrompt
        case .granted:
            break
        }

        switch location {
        case .denied, .restricted:
            return .permissionDenied(target: .location)
        case .notDetermined:
            return .requestPrompt
        case .granted:
            break
        }

        let chip: ChipState
        if isInFlight {
            chip = .disabled
        } else if isPending {
            chip = .pending
        } else {
            chip = .idle
        }
        return .cameraActive(chip: chip)
    }
}
