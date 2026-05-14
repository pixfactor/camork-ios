import AVFoundation
import UIKit
import Combine

enum CaptureMode {
    case photo
    case video
}

@MainActor
final class CameraManager: NSObject, ObservableObject {
    @Published var isSessionRunning: Bool = false
    @Published var currentZoomFactor: CGFloat = 1.0
    @Published var flashMode: AVCaptureDevice.FlashMode = .auto
    @Published var isRecording: Bool = false
    @Published var captureMode: CaptureMode = .photo
    @Published var currentCameraPosition: AVCaptureDevice.Position = .back
    @Published var isAuthorized: Bool = false
    @Published var setupError: String?

    private(set) var captureSession = AVCaptureSession()
    private var photoOutput = AVCapturePhotoOutput()
    private var movieOutput = AVCaptureMovieFileOutput()
    private var currentVideoInput: AVCaptureDeviceInput?

    private var photoCaptureCompletion: ((Data?) -> Void)?
    private var recordingCompletion: ((URL?) -> Void)?

    private let sessionQueue = DispatchQueue(label: "com.camork.session", qos: .userInitiated)

    var isSimulator: Bool {
        #if targetEnvironment(simulator)
        return true
        #else
        return false
        #endif
    }

    // MARK: - Session Setup

    func checkPermissionsAndSetup() async {
        #if targetEnvironment(simulator)
        isAuthorized = true
        #else
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            isAuthorized = true
            await setupSession()
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            isAuthorized = granted
            if granted { await setupSession() }
        case .denied, .restricted:
            isAuthorized = false
            setupError = "카메라 접근 권한이 필요합니다. 설정에서 허용해 주세요."
        @unknown default:
            break
        }
        #endif
    }

    func setupSession() async {
        await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self else { continuation.resume(); return }
                self.configureSession()
                continuation.resume()
            }
        }
    }

    private func configureSession() {
        captureSession.beginConfiguration()
        defer { captureSession.commitConfiguration() }

        captureSession.sessionPreset = .photo

        // Video input
        guard let videoDevice = bestCamera(for: currentCameraPosition) else {
            Task { @MainActor in self.setupError = "카메라를 찾을 수 없습니다." }
            return
        }

        do {
            let videoInput = try AVCaptureDeviceInput(device: videoDevice)
            if captureSession.canAddInput(videoInput) {
                captureSession.addInput(videoInput)
                currentVideoInput = videoInput
            }
        } catch {
            Task { @MainActor in self.setupError = "카메라 입력 오류: \(error.localizedDescription)" }
            return
        }

        // Audio input
        if let audioDevice = AVCaptureDevice.default(for: .audio),
           let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
           captureSession.canAddInput(audioInput) {
            captureSession.addInput(audioInput)
        }

        // Photo output
        if captureSession.canAddOutput(photoOutput) {
            captureSession.addOutput(photoOutput)
            photoOutput.isHighResolutionCaptureEnabled = true
            if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
                // HEVC available
            }
        }

        // Movie output
        if captureSession.canAddOutput(movieOutput) {
            captureSession.addOutput(movieOutput)
        }
    }

    private func bestCamera(for position: AVCaptureDevice.Position) -> AVCaptureDevice? {
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.builtInTripleCamera, .builtInDualWideCamera, .builtInDualCamera, .builtInWideAngleCamera],
            mediaType: .video,
            position: position
        )
        return discoverySession.devices.first ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position)
    }

    // MARK: - Session Lifecycle

    func startSession() {
        sessionQueue.async { [weak self] in
            guard let self, !self.captureSession.isRunning else { return }
            self.captureSession.startRunning()
            Task { @MainActor in self.isSessionRunning = true }
        }
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self, self.captureSession.isRunning else { return }
            self.captureSession.stopRunning()
            Task { @MainActor in self.isSessionRunning = false }
        }
    }

    // MARK: - Camera Switch

    func switchCamera() {
        let newPosition: AVCaptureDevice.Position = currentCameraPosition == .back ? .front : .back
        sessionQueue.async { [weak self] in
            guard let self else { return }
            guard let newDevice = self.bestCamera(for: newPosition),
                  let newInput = try? AVCaptureDeviceInput(device: newDevice) else { return }

            self.captureSession.beginConfiguration()
            if let current = self.currentVideoInput {
                self.captureSession.removeInput(current)
            }
            if self.captureSession.canAddInput(newInput) {
                self.captureSession.addInput(newInput)
                self.currentVideoInput = newInput
            }
            self.captureSession.commitConfiguration()
            Task { @MainActor in
                self.currentCameraPosition = newPosition
                self.currentZoomFactor = 1.0
            }
        }
    }

    // MARK: - Flash

    func setFlashMode(_ mode: AVCaptureDevice.FlashMode) {
        flashMode = mode
        // For video mode, control torch
        if captureMode == .video {
            setTorch(for: mode)
        }
    }

    private func setTorch(for flashMode: AVCaptureDevice.FlashMode) {
        guard let device = currentVideoInput?.device, device.hasTorch else { return }
        try? device.lockForConfiguration()
        switch flashMode {
        case .on:
            try? device.setTorchModeOn(level: 1.0)
        case .off:
            device.torchMode = .off
        case .auto:
            device.torchMode = .auto
        @unknown default:
            device.torchMode = .off
        }
        device.unlockForConfiguration()
    }

    // MARK: - Zoom

    func setZoom(_ factor: CGFloat) {
        guard let device = currentVideoInput?.device else { return }
        let minZoom = device.minAvailableVideoZoomFactor
        let maxZoom = min(device.maxAvailableVideoZoomFactor, 10.0)
        let clampedFactor = max(minZoom, min(factor, maxZoom))

        sessionQueue.async {
            try? device.lockForConfiguration()
            device.videoZoomFactor = clampedFactor
            device.unlockForConfiguration()
        }
        currentZoomFactor = clampedFactor
    }

    // MARK: - Capture Mode Switch

    func setCaptureMode(_ mode: CaptureMode) {
        guard mode != captureMode else { return }
        captureMode = mode

        // Update session preset
        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = mode == .video ? .hd1920x1080 : .photo
            self.captureSession.commitConfiguration()
        }

        // Turn off torch when switching to photo
        if mode == .photo {
            setTorch(for: .off)
        }
    }

    // MARK: - Photo Capture

    func capturePhoto(completion: @escaping (Data?) -> Void) {
        #if targetEnvironment(simulator)
        // 시뮬레이터: 더미 검정 이미지 생성
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 1080, height: 1920))
        let dummyData = renderer.jpegData(withCompressionQuality: 0.8) { ctx in
            UIColor.darkGray.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 1080, height: 1920))
            let text = "Simulator\n\(Date().formatted())" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: UIColor.white,
                .font: UIFont.systemFont(ofSize: 40, weight: .medium)
            ]
            text.draw(at: CGPoint(x: 300, y: 900), withAttributes: attrs)
        }
        completion(dummyData)
        #else
        photoCaptureCompletion = completion
        let settings = AVCapturePhotoSettings()

        if captureMode == .photo {
            settings.flashMode = flashMode
        }

        if photoOutput.availablePhotoCodecTypes.contains(.hevc) {
            // Use HEVC if available
        }

        photoOutput.capturePhoto(with: settings, delegate: self)
        #endif
    }

    // MARK: - Video Recording

    func startRecording(to url: URL) {
        guard !movieOutput.isRecording else { return }

        // Enable torch if flash is on for video
        if flashMode == .on {
            setTorch(for: .on)
        }

        sessionQueue.async { [weak self] in
            guard let self else { return }
            self.movieOutput.startRecording(to: url, recordingDelegate: self)
        }
        isRecording = true
    }

    func stopRecording() {
        guard movieOutput.isRecording else { return }
        movieOutput.stopRecording()
        setTorch(for: .off)
    }

    // MARK: - Temporary Video URL

    func temporaryVideoURL() -> URL {
        let fileName = UUID().uuidString + ".mov"
        return FileManager.default.temporaryDirectory.appendingPathComponent(fileName)
    }
}

// MARK: - AVCapturePhotoCaptureDelegate

extension CameraManager: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(
        _ output: AVCapturePhotoOutput,
        didFinishProcessingPhoto photo: AVCapturePhoto,
        error: Error?
    ) {
        let data = photo.fileDataRepresentation()
        Task { @MainActor in
            self.photoCaptureCompletion?(data)
            self.photoCaptureCompletion = nil
        }
    }
}

// MARK: - AVCaptureFileOutputRecordingDelegate

extension CameraManager: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        let url: URL? = error == nil ? outputFileURL : nil
        Task { @MainActor in
            self.isRecording = false
            self.recordingCompletion?(url)
            self.recordingCompletion = nil
        }
    }

    func setRecordingCompletion(_ completion: @escaping (URL?) -> Void) {
        recordingCompletion = completion
    }
}
