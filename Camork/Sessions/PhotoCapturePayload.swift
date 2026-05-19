import Foundation

/// AVFoundation 콜백에서 MediaStorage actor로 hop할 때 사용하는 Sendable payload
/// (ADR #6).
///
/// `AVCapturePhoto` 같은 non-Sendable 객체는 actor로 hop하지 않고, callback queue
/// (nonisolated)에서 `Data` + metadata만 추출해 본 struct로 조립한다.
struct PhotoCapturePayload: Sendable {
    let data: Data
    let capturedAt: Date
    let location: LocationSnapshot?
    let exif: ExifData?
}
