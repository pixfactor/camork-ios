import AVFoundation
import Foundation

/// MediaCapture 캡쳐 흐름에서 발생 가능한 에러 — fileDataRepresentation 실패 등
/// AVFoundation이 미반환하는 경우.
enum CaptureError: Error, Sendable, Equatable {
    case noImageData
}

/// AVCapturePhotoCaptureDelegate를 채택하여 capture-result를 `PhotoCapturePayload`로
/// 조립한 후 `@Sendable` 콜백으로 emit. ADR #6 흐름의 첫 단계.
///
/// 책임 경계:
/// - AVFoundation callback queue (nonisolated)에서 `photo.fileDataRepresentation()`,
///   `ExifBuilder.build(from:)`, `locationService.latestKnown()`만 수행.
/// - `AVCapturePhoto` 같은 non-Sendable 객체는 hop 금지 — Data + Sendable metadata만
///   `PhotoCapturePayload`로 packing.
/// - MediaStorage actor hop은 본 클래스 책임 외 — Phase 2c CameraScreen이 callback
///   안에서 `Task { @MainActor in await mediaStorage.saveCapture(payload) }` 수행.
/// - SwiftUI 상태 변경 없음 — UI 갱신은 caller가 callback 결과를 받아 처리.
final class MediaCapture: NSObject, AVCapturePhotoCaptureDelegate, @unchecked Sendable {
    private let locationService: LocationService
    private let onPayloadReady: @Sendable (Result<PhotoCapturePayload, Error>) -> Void

    init(
        locationService: LocationService,
        onPayloadReady: @escaping @Sendable (Result<PhotoCapturePayload, Error>) -> Void
    ) {
        self.locationService = locationService
        self.onPayloadReady = onPayloadReady
        super.init()
    }

    /// AVFoundation은 capture lifecycle 동안 delegate를 강참조 — 단일 capture에 한정.
    /// 후속 capture를 위해 caller(Phase 2c CameraScreen)가 `MediaCapture` 인스턴스를
    /// strong reference로 보유.
    func capture(
        with photoOutput: AVCapturePhotoOutput,
        settings: AVCapturePhotoSettings = AVCapturePhotoSettings()
    ) {
        photoOutput.capturePhoto(with: settings, delegate: self)
    }

    // MARK: - AVCapturePhotoCaptureDelegate

    func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        if let error {
            onPayloadReady(.failure(error))
            return
        }
        guard let data = photo.fileDataRepresentation() else {
            onPayloadReady(.failure(CaptureError.noImageData))
            return
        }
        let exif = ExifBuilder.build(from: photo)
        let snapshot = locationService.latestKnown()
        let payload = PhotoCapturePayload(
            data: data,
            capturedAt: Date(),
            location: snapshot,
            exif: exif
        )
        onPayloadReady(.success(payload))
    }
}
