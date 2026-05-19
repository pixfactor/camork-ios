import AVFoundation
import Foundation

/// 카메라 facing — Phase 2a.3 CameraSession이 AVCaptureDevice.Position으로 매핑.
enum CameraFacing: Sendable, Equatable {
    case back
    case front
}

/// 출력 종류 — v1 Core는 photo only. v1.2 video는 `.movie` 추가 예정 (ADR #11과 동일 정책).
enum CameraOutputKind: Sendable, Hashable {
    case photo
}

/// session preset — v1 Core는 photo preset only. 4K 등 movie preset은 v1.2에서.
enum CameraSessionPreset: Sendable, Equatable {
    case photo
}

/// CameraSession이 소비할 value-only configuration descriptor. AVCaptureSession을
/// 직접 인스턴스화하지 않으므로 단위 테스트에서 안전하게 검증 가능.
struct CameraConfiguration: Sendable, Equatable {
    let deviceFacing: CameraFacing
    let sessionPreset: CameraSessionPreset
    let outputs: Set<CameraOutputKind>
}

/// pure builder — value-only descriptor 반환. AVFoundation 객체 인스턴스화는 Phase 2a.3
/// CameraSession이 본 descriptor를 consume할 때 일어난다.
enum CameraSessionBuilder {
    static func makeConfiguration(facing: CameraFacing = .back) -> CameraConfiguration {
        CameraConfiguration(
            deviceFacing: facing,
            sessionPreset: .photo,
            outputs: [.photo]
        )
    }
}

// MARK: - AVFoundation bridges (Phase 2a.3 진입점)

extension CameraFacing {
    var avPosition: AVCaptureDevice.Position {
        switch self {
        case .back: return .back
        case .front: return .front
        }
    }
}

extension CameraSessionPreset {
    var avPreset: AVCaptureSession.Preset {
        switch self {
        case .photo: return .photo
        }
    }
}
