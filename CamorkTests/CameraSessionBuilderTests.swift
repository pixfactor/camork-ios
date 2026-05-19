import Testing
import AVFoundation
@testable import Camork

@Suite("CameraSessionBuilder")
struct CameraSessionBuilderTests {

    @Test("default config — back facing + photo preset + photo output")
    func defaultConfig() {
        let config = CameraSessionBuilder.makeConfiguration()
        #expect(config.deviceFacing == .back)
        #expect(config.sessionPreset == .photo)
        #expect(config.outputs.contains(.photo))
    }

    @Test("front facing 전환")
    func frontFacing() {
        let config = CameraSessionBuilder.makeConfiguration(facing: .front)
        #expect(config.deviceFacing == .front)
        #expect(config.sessionPreset == .photo)
        #expect(config.outputs.contains(.photo))
    }

    @Test("CameraFacing → AVCaptureDevice.Position 매핑")
    func avPositionMapping() {
        #expect(CameraFacing.back.avPosition == .back)
        #expect(CameraFacing.front.avPosition == .front)
    }

    @Test("CameraSessionPreset → AVCaptureSession.Preset 매핑")
    func avPresetMapping() {
        #expect(CameraSessionPreset.photo.avPreset == .photo)
    }
}
