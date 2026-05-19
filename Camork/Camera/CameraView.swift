import AVFoundation
import SwiftUI
import UIKit

/// AVCaptureSession을 SwiftUI에 노출하는 thin UIViewControllerRepresentable.
///
/// 책임 경계:
/// - 본 wrapper는 layer ↔ session 결선만 담당. start/stop side-effect 없음 — ScenePhase
///   라이프사이클은 Phase 2c.4 CameraScreen이 onChange(of: scenePhase)로 처리.
/// - AVCaptureSession은 외부에서 생성/소유 (Phase 2c.1 DependencyContainer).
///   본 wrapper는 session 인스턴스를 재생성하지 않음 — updateUIViewController는 layer의
///   session 참조만 동기화 (preview 끊김 방지).
struct CameraView: UIViewControllerRepresentable {
    let session: AVCaptureSession

    func makeUIViewController(context: Context) -> CameraPreviewController {
        let controller = CameraPreviewController()
        controller.configure(session: session)
        return controller
    }

    func updateUIViewController(_ controller: CameraPreviewController, context: Context) {
        controller.updateSession(session)
    }
}

/// `CameraPreviewView`를 자신의 root view로 owner. UIViewController로 wrapping해두면
/// 추후 orientation lock / status bar / safeArea 등 ViewController-level hook을 추가하기
/// 쉬워진다 (현 시점에는 dependency 없음).
final class CameraPreviewController: UIViewController {
    private let previewView = CameraPreviewView()

    override func loadView() {
        view = previewView
    }

    func configure(session: AVCaptureSession) {
        previewView.previewLayer.session = session
        previewView.previewLayer.videoGravity = .resizeAspectFill
    }

    func updateSession(_ session: AVCaptureSession) {
        // 동일 instance면 layer 재할당 회피 — preview 끊김 방지.
        guard previewView.previewLayer.session !== session else { return }
        previewView.previewLayer.session = session
    }
}

/// `layerClass` override로 layer를 `AVCaptureVideoPreviewLayer`로 강제. 본 invariant
/// 가 force-cast `as!`를 안전하게 만든다 (런타임에 다른 타입이면 프로그래머 오류).
final class CameraPreviewView: UIView {
    override static var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        // `layerClass` override가 보장 — invariant 위반 시 즉시 크래시(프로그래머 오류).
        layer as! AVCaptureVideoPreviewLayer
    }
}

#Preview {
    // 시뮬레이터엔 카메라가 없으므로 CameraSession init이 throw 가능 → preview에는
    // 빈 AVCaptureSession()만 주입. 검정 화면이 표시되지만 크래시 없음.
    CameraView(session: AVCaptureSession())
        .ignoresSafeArea()
}
