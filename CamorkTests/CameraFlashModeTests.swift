import AVFoundation
import Testing
@testable import Camork

@Suite("CameraFlashMode")
struct CameraFlashModeTests {
    @Test("next cycles through off, auto, on")
    func nextCycle() {
        #expect(CameraFlashMode.off.next == .auto)
        #expect(CameraFlashMode.auto.next == .on)
        #expect(CameraFlashMode.on.next == .off)
    }

    @Test("mode maps to AVFoundation flash modes")
    func avFlashModeMapping() {
        #expect(CameraFlashMode.off.avFlashMode == AVCaptureDevice.FlashMode.off)
        #expect(CameraFlashMode.auto.avFlashMode == AVCaptureDevice.FlashMode.auto)
        #expect(CameraFlashMode.on.avFlashMode == AVCaptureDevice.FlashMode.on)
    }
}
