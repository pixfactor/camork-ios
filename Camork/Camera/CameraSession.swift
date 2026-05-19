import AVFoundation
import Foundation

/// CameraSession 초기화 실패 — 시뮬레이터/디바이스 없음 등 비치명적 상황을 force-unwrap
/// 없이 typed error로 전파. UI는 본 enum 매칭으로 retry / 안내 분기.
enum CameraSessionError: Error, Sendable, Equatable {
    case noDevice
    case cannotAddInput
    case cannotAddOutput
}

/// AVCaptureSession + AVCapturePhotoOutput을 소유하는 thin wrapper.
///
/// 책임 경계:
/// - 본 클래스는 AVFoundation 객체 owner + 시작/정지 라이프사이클.
/// - 권한 요청은 `PermissionsService` (Phase 2a.1), preview 표시는 Phase 2c CameraView가
///   `session`을 읽기 전용으로 참조해 `AVCaptureVideoPreviewLayer` 구성.
/// - capture 트리거 + delegate 콜백은 Phase 2b.2 MediaCapture가 `photoOutput`을 사용.
///
/// `CameraConfiguration`을 consume해 beginConfiguration/commitConfiguration 트랜잭션
/// 안에서 preset → wide-angle device → input → photo output 순서로 구성.
///
/// **Concurrency contract** (`@unchecked Sendable`):
/// - 모든 configuration은 `init` 한 번에 완료 — 이후 본 클래스는 reconfigure하지 않음.
/// - stored property (`session`, `photoOutput`, `configuration`)는 전부 `let` — 본
///   클래스가 캡쳐 후 노출하는 외부 reference도 변경되지 않음.
/// - Phase 2c.4 CameraScreen이 **단일 private serial queue**(`cameraSessionQueue`)에서
///   `start()`/`stop()`만 호출. 다른 호출자/큐 진입점 없음.
/// - `@unchecked Sendable` 옵트인의 유일한 목적은 위의 off-main lifecycle boundary로
///   owner reference를 안전하게 넘기는 것 — AVCaptureSession이 모든 큐에서 외부
///   동기화 없이 사용 가능하다는 일반 주장이 **아님**.
///
/// **Directive** (앞으로의 변경에서 지킬 것):
/// - 본 클래스에 가변 stored property를 추가하거나 여러 큐에서 reconfigure (`beginConfiguration`
///   /`addInput`/`addOutput` 등) 호출이 필요해지면, 위 contract가 깨진다.
///   그 시점에는 `@unchecked Sendable`을 떼고 serial queue ownership을 본 클래스 내부
///   로 이전하거나, actor wrapping을 재검토해야 한다.
final class CameraSession: @unchecked Sendable {
    let session: AVCaptureSession
    let photoOutput: AVCapturePhotoOutput
    let configuration: CameraConfiguration

    init(configuration: CameraConfiguration) throws {
        self.configuration = configuration
        self.session = AVCaptureSession()
        self.photoOutput = AVCapturePhotoOutput()

        session.beginConfiguration()
        defer { session.commitConfiguration() }

        let preset = configuration.sessionPreset.avPreset
        if session.canSetSessionPreset(preset) {
            session.sessionPreset = preset
        }

        guard let device = AVCaptureDevice.default(
            .builtInWideAngleCamera,
            for: .video,
            position: configuration.deviceFacing.avPosition
        ) else {
            throw CameraSessionError.noDevice
        }

        let input: AVCaptureDeviceInput
        do {
            input = try AVCaptureDeviceInput(device: device)
        } catch {
            throw CameraSessionError.noDevice
        }

        guard session.canAddInput(input) else {
            throw CameraSessionError.cannotAddInput
        }
        session.addInput(input)

        if configuration.outputs.contains(.photo) {
            guard session.canAddOutput(photoOutput) else {
                throw CameraSessionError.cannotAddOutput
            }
            session.addOutput(photoOutput)
        }
    }

    /// AVFoundation 권장사항: background queue에서 호출.
    func start() {
        guard !session.isRunning else { return }
        session.startRunning()
    }

    func stop() {
        guard session.isRunning else { return }
        session.stopRunning()
    }
}
