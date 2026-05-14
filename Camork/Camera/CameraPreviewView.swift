import SwiftUI
import AVFoundation

struct CameraPreviewView: UIViewRepresentable {
    let cameraManager: CameraManager

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.backgroundColor = .black
        view.videoPreviewLayer.session = cameraManager.captureSession
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.videoPreviewLayer.connection?.videoRotationAngle = 90
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        // Session updates are managed by CameraManager
        DispatchQueue.main.async {
            uiView.videoPreviewLayer.session = self.cameraManager.captureSession
        }
    }
}

// MARK: - PreviewUIView

final class PreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        videoPreviewLayer.frame = bounds
        updateOrientation()
    }

    private func updateOrientation() {
        guard let connection = videoPreviewLayer.connection,
              connection.isVideoRotationAngleSupported(90) else { return }

        let scene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first
        let orientation = scene?.interfaceOrientation ?? .portrait

        let angle: CGFloat
        switch orientation {
        case .portrait:            angle = 90
        case .portraitUpsideDown:  angle = 270
        case .landscapeLeft:       angle = 180
        case .landscapeRight:      angle = 0
        default:                   angle = 90
        }

        if connection.isVideoRotationAngleSupported(angle) {
            connection.videoRotationAngle = angle
        }
    }
}
