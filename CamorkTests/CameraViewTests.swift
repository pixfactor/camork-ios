import Testing
import AVFoundation
@testable import Camork

@Suite("CameraView")
struct CameraViewTests {

    /// `CameraPreviewView.previewLayer`의 force-cast `as!`가 안전하려면 layerClass
    /// override가 정확히 `AVCaptureVideoPreviewLayer.self`여야 함. 본 invariant가
    /// 깨지면 런타임 크래시가 나므로 메타데이터 수준에서 회귀 방지.
    @Test("CameraPreviewView.layerClass 는 AVCaptureVideoPreviewLayer (force-cast invariant)")
    func previewViewLayerClassIsAVCaptureVideoPreviewLayer() {
        #expect(
            ObjectIdentifier(CameraPreviewView.layerClass)
                == ObjectIdentifier(AVCaptureVideoPreviewLayer.self)
        )
    }
}
