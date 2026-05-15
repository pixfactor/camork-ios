import SwiftUI
import SwiftData
import AVFoundation
import CoreLocation

private struct CameraFeedback: Identifiable, Equatable {
    let id = UUID()
    let message: String
    let isError: Bool
}

struct CameraContainerView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Folder.sortOrder) private var folders: [Folder]

    @StateObject private var cameraManager = CameraManager()
    @StateObject private var locationManager = LocationManager()
    @StateObject private var batteryMonitor = BatteryMonitor()
    @AppStorage("camera.lastSelectedFolderID") private var lastSelectedFolderID = ""

    @State private var selectedFolder: Folder?
    @State private var showFolderPicker = false
    @State private var watermarkEnabled = false
    @State private var showThumbnail = false
    @State private var lastThumbnailData: Data?
    @State private var isSaving = false
    @State private var recordingDuration: Double = 0
    @State private var recordingTimer: Timer?
    @State private var showFolderRequiredAlert = false
    @State private var feedback: CameraFeedback?
    @State private var feedbackDismissTask: Task<Void, Never>?

    @State private var showMemoSheet = false
    @State private var lastCapturedItem: MediaItem?
    @AppStorage("camera.skipMemoSheet") private var skipMemoSheetSetting = false

    @State private var isStorageLow = false
    @State private var freeSpaceString = ""

    @State private var lastZoomFactor: CGFloat = 1.0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if cameraManager.isAuthorized {
                cameraPreview
                overlayUI
            } else {
                permissionDeniedView
            }
        }
        .onAppear {
            Task {
                await cameraManager.checkPermissionsAndSetup()
                if cameraManager.isAuthorized {
                    cameraManager.startSession()
                }
                locationManager.startUpdating()

                let storageLow = await StorageWarningService.shared.isStorageLow()
                let space = await StorageWarningService.shared.formattedFreeSpace()
                isStorageLow = storageLow
                freeSpaceString = space
            }
            applySelectedFolderPreference()
        }
        .onDisappear {
            cameraManager.stopSession()
            locationManager.stopUpdating()
            batteryMonitor.stopMonitoring()
            stopRecordingTimer()
            feedbackDismissTask?.cancel()
        }
        .onChange(of: folders.map(\.id)) { _, _ in
            applySelectedFolderPreference()
        }
        .onChange(of: selectedFolder?.id) { _, _ in
            persistSelectedFolderPreference()
        }
        .sheet(isPresented: $showFolderPicker) {
            FolderPickerView(selectedFolder: $selectedFolder)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showMemoSheet) {
            if let item = lastCapturedItem {
                MemoTemplateSheet(item: item) { skip in
                    skipMemoSheetSetting = skip
                    showMemoSheet = false
                    showFeedback("\(selectedFolder?.name ?? "선택한 폴더")에 저장했어요.")
                }
            }
        }
        .statusBarHidden(true)
        .alert("폴더를 선택하세요", isPresented: $showFolderRequiredAlert) {
            Button("폴더 선택") { showFolderPicker = true }
            Button("취소", role: .cancel) {}
        } message: {
            Text("촬영한 사진을 저장할 폴더를 먼저 선택해 주세요.")
        }
    }

    private var cameraPreview: some View {
        CameraPreviewView(cameraManager: cameraManager)
            .ignoresSafeArea()
            .gesture(pinchGesture)
    }

    private var pinchGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let newFactor = lastZoomFactor * value
                cameraManager.setZoom(newFactor)
            }
            .onEnded { _ in
                lastZoomFactor = cameraManager.currentZoomFactor
            }
    }

    private var overlayUI: some View {
        VStack(spacing: 0) {
            topBar
            if let feedback {
                feedbackBanner(feedback)
                    .padding(.top, 12)
            }
            if isStorageLow {
                warningBanner(message: "저장 공간 부족 (\(freeSpaceString))", icon: "internaldrive")
                    .padding(.top, 12)
            }
            if batteryMonitor.isLowBattery {
                warningBanner(message: "배터리 부족 (\(Int(batteryMonitor.batteryLevel * 100))%)", icon: "battery.25")
                    .padding(.top, isStorageLow ? 4 : 12)
            }
            Spacer()
            bottomBar
        }
        .padding(.bottom, 8)
    }

    private var topBar: some View {
        HStack(spacing: 20) {
            flashButton
            Spacer()
            folderButton
            Spacer()
            watermarkButton
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(.black.opacity(0.4))
    }

    private var flashButton: some View {
        Button {
            let modes: [AVCaptureDevice.FlashMode] = [.auto, .on, .off]
            let currentIndex = modes.firstIndex(of: cameraManager.flashMode) ?? 0
            let nextMode = modes[(currentIndex + 1) % modes.count]
            cameraManager.setFlashMode(nextMode)
        } label: {
            Image(systemName: flashIconName)
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(flashIconColor)
                .frame(width: 44, height: 44)
        }
    }

    private var flashIconName: String {
        switch cameraManager.flashMode {
        case .auto: return "bolt.badge.a.fill"
        case .on: return "bolt.fill"
        case .off: return "bolt.slash.fill"
        @unknown default: return "bolt.slash.fill"
        }
    }

    private var flashIconColor: Color {
        cameraManager.flashMode == .on ? .yellow : .white
    }

    private var folderButton: some View {
        Button {
            showFolderPicker = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "folder.fill")
                    .font(.system(size: 16))
                Text(selectedFolder?.name ?? "폴더 선택")
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1).truncationMode(.tail)
                Image(systemName: "chevron.down")
                    .font(.system(size: 11))
            }
            .foregroundStyle(selectedFolder == nil ? .yellow : .white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                (selectedFolder == nil ? Color.yellow : .white).opacity(0.2),
                in: Capsule()
            )
        }
    }

    private var watermarkButton: some View {
        Button {
            watermarkEnabled.toggle()
        } label: {
            Image(systemName: watermarkEnabled ? "clock.fill" : "clock")
                .font(.system(size: 22, weight: .medium))
                .foregroundStyle(watermarkEnabled ? .yellow : .white)
                .frame(width: 44, height: 44)
        }
    }

    private var bottomBar: some View {
        HStack(alignment: .center, spacing: 0) {
            thumbnailView
                .frame(maxWidth: .infinity)

            shutterButton

            cameraSwitchButton
                .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 16)
        .background(.black.opacity(0.5))
        .overlay(alignment: .top) {
            captureModeToggle
                .offset(y: -56)
        }
    }

    private var captureModeToggle: some View {
        HStack(spacing: 0) {
            modeButton(title: "사진", mode: .photo)
            modeButton(title: "동영상", mode: .video)
        }
        .background(Capsule().fill(.white.opacity(0.15)))
    }

    private func modeButton(title: String, mode: CaptureMode) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                cameraManager.setCaptureMode(mode)
            }
        } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(cameraManager.captureMode == mode ? .black : .white)
                .padding(.horizontal, 18)
                .padding(.vertical, 7)
                .background(
                    Capsule()
                        .fill(cameraManager.captureMode == mode ? .white : .clear)
                )
        }
    }

    private var shutterButton: some View {
        Button {
            handleShutter()
        } label: {
            ZStack {
                Circle()
                    .fill(
                        cameraManager.captureMode == .video && cameraManager.isRecording
                        ? .red
                        : .white
                    )
                    .frame(
                        width: cameraManager.isRecording ? 48 : 68,
                        height: cameraManager.isRecording ? 48 : 68
                    )

                Circle()
                    .stroke(.white, lineWidth: 4)
                    .frame(width: 78, height: 78)

                if cameraManager.isRecording {
                    Text(formatDuration(recordingDuration))
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .offset(y: 50)
                }
            }
        }
        .disabled(isSaving || isStorageLow)
        .animation(.easeInOut(duration: 0.15), value: cameraManager.isRecording)
    }

    private var cameraSwitchButton: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.3)) {
                cameraManager.switchCamera()
                lastZoomFactor = 1.0
            }
        } label: {
            Image(systemName: "arrow.triangle.2.circlepath.camera")
                .font(.system(size: 26, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
        }
    }

    @ViewBuilder
    private var thumbnailView: some View {
        if showThumbnail, let data = lastThumbnailData,
           let uiImage = UIImage(data: data) {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 52, height: 52)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(.white, lineWidth: 1.5)
                )
                .transition(.scale.combined(with: .opacity))
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(0.1))
                .frame(width: 52, height: 52)
        }
    }

    private func feedbackBanner(_ feedback: CameraFeedback) -> some View {
        Text(feedback.message)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(feedback.isError ? Color.red.opacity(0.92) : Color.green.opacity(0.9))
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
            .padding(.horizontal, 20)
            .transition(.move(edge: .top).combined(with: .opacity))
    }

    private func warningBanner(message: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
            Text(message)
                .font(.caption.weight(.medium))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color.orange.opacity(0.92))
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.18), radius: 10, y: 4)
        .padding(.horizontal, 20)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var permissionDeniedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.system(size: 60))
                .foregroundStyle(.gray)
            Text("카메라 접근 권한 필요")
                .font(.title3.bold())
                .foregroundStyle(.white)
            Text(cameraManager.setupError ?? "설정에서 카메라 접근을 허용해 주세요.")
                .font(.body)
                .foregroundStyle(.gray)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Button("설정 열기") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private func handleShutter() {
        guard selectedFolder != nil else {
            showFolderRequiredAlert = true
            return
        }

        switch cameraManager.captureMode {
        case .photo:
            capturePhoto()
        case .video:
            if cameraManager.isRecording {
                stopVideoRecording()
            } else {
                startVideoRecording()
            }
        }
    }

    private func capturePhoto() {
        isSaving = true

        cameraManager.capturePhoto { [self] data in
            guard var imageData = data else {
                isSaving = false
                return
            }

            Task {
                if watermarkEnabled {
                    let location = locationManager.currentLocation
                    imageData = WatermarkRenderer.applyWatermark(
                        to: imageData,
                        date: Date(),
                        location: location
                    ) ?? imageData
                }

                await savePhoto(data: imageData)
                await MainActor.run { isSaving = false }
            }
        }
    }

    private func savePhoto(data: Data) async {
        let fileName = FileStorageManager.shared.generateUniqueFileName(extension: "jpg")
        let thumbnailFileName = FileStorageManager.shared.generateUniqueFileName(extension: "jpg")

        do {
            _ = try await FileStorageManager.shared.saveMedia(data: data, fileName: fileName)

            if let thumbData = ThumbnailGenerator.generateImageThumbnail(from: data) {
                _ = try await FileStorageManager.shared.saveMedia(data: thumbData, fileName: thumbnailFileName)
                await MainActor.run {
                    withAnimation(.spring(duration: 0.3)) {
                        lastThumbnailData = thumbData
                        showThumbnail = true
                    }
                }
            }

            let location = locationManager.currentLocation
            let item = MediaItem(
                mediaType: .photo,
                fileName: fileName,
                thumbnailFileName: thumbnailFileName,
                memo: "",
                capturedAt: Date(),
                latitude: location?.coordinate.latitude,
                longitude: location?.coordinate.longitude
            )

            await MainActor.run {
                modelContext.insert(item)
                if let folder = selectedFolder {
                    item.folder = folder
                }
                if !skipMemoSheetSetting {
                    lastCapturedItem = item
                    showMemoSheet = true
                } else {
                    showFeedback("\(selectedFolder?.name ?? "선택한 폴더")에 사진을 저장했어요.")
                }
            }
        } catch {
            await MainActor.run {
                showFeedback("사진 저장에 실패했습니다. 다시 시도해 주세요.", isError: true)
            }
        }
    }

    private func startVideoRecording() {
        let url = cameraManager.temporaryVideoURL()
        cameraManager.setRecordingCompletion { [self] outputURL in
            guard let outputURL else { return }
            Task { await saveVideo(from: outputURL) }
        }
        cameraManager.startRecording(to: url)
        startRecordingTimer()
    }

    private func stopVideoRecording() {
        cameraManager.stopRecording()
        stopRecordingTimer()
    }

    private func saveVideo(from tempURL: URL) async {
        let fileName = FileStorageManager.shared.generateUniqueFileName(extension: "mov")
        let thumbnailFileName = FileStorageManager.shared.generateUniqueFileName(extension: "jpg")

        do {
            let savedURL = try await FileStorageManager.shared.saveVideo(from: tempURL, fileName: fileName)

            if let thumbData = ThumbnailGenerator.generateVideoThumbnail(from: savedURL) {
                _ = try await FileStorageManager.shared.saveMedia(data: thumbData, fileName: thumbnailFileName)
                await MainActor.run {
                    withAnimation(.spring(duration: 0.3)) {
                        lastThumbnailData = thumbData
                        showThumbnail = true
                    }
                }
            }

            let location = locationManager.currentLocation
            let item = MediaItem(
                mediaType: .video,
                fileName: fileName,
                thumbnailFileName: thumbnailFileName,
                memo: "",
                capturedAt: Date(),
                latitude: location?.coordinate.latitude,
                longitude: location?.coordinate.longitude,
                duration: recordingDuration
            )

            await MainActor.run {
                modelContext.insert(item)
                if let folder = selectedFolder {
                    item.folder = folder
                }
                recordingDuration = 0
                if !skipMemoSheetSetting {
                    lastCapturedItem = item
                    showMemoSheet = true
                } else {
                    showFeedback("\(selectedFolder?.name ?? "선택한 폴더")에 동영상을 저장했어요.")
                }
            }
        } catch {
            await MainActor.run {
                showFeedback("동영상 저장에 실패했습니다. 다시 시도해 주세요.", isError: true)
            }
        }
    }

    private func startRecordingTimer() {
        recordingDuration = 0
        recordingTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            recordingDuration += 1
        }
    }

    private func stopRecordingTimer() {
        recordingTimer?.invalidate()
        recordingTimer = nil
    }

    private func formatDuration(_ seconds: Double) -> String {
        let value = Int(seconds)
        return String(format: "%02d:%02d", value / 60, value % 60)
    }

    private func applySelectedFolderPreference() {
        guard !folders.isEmpty else {
            selectedFolder = nil
            lastSelectedFolderID = ""
            return
        }

        if let selectedFolder,
           folders.contains(where: { $0.id == selectedFolder.id }) {
            return
        }

        if let storedID = UUID(uuidString: lastSelectedFolderID),
           let storedFolder = folders.first(where: { $0.id == storedID }) {
            selectedFolder = storedFolder
            return
        }

        selectedFolder = folders.first
    }

    private func persistSelectedFolderPreference() {
        lastSelectedFolderID = selectedFolder?.id.uuidString ?? ""
    }

    private func showFeedback(_ message: String, isError: Bool = false) {
        feedbackDismissTask?.cancel()
        let nextFeedback = CameraFeedback(message: message, isError: isError)

        withAnimation(.spring(duration: 0.28)) {
            feedback = nextFeedback
        }

        feedbackDismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard feedback?.id == nextFeedback.id else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    feedback = nil
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    CameraContainerView()
        .modelContainer(for: [Folder.self, MediaItem.self], inMemory: true)
}
#endif
