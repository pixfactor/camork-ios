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
final class CameraSession {
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
