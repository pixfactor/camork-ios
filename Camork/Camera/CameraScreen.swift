import AVFoundation
import SwiftUI

/// 시작/정지 같은 blocking AVFoundation 호출 전용 serial queue.
/// 메인 스레드에서 `startRunning`/`stopRunning` 호출은 UI hitches를 유발하므로 격리.
private let cameraSessionQueue = DispatchQueue(label: "com.camork.camera-session", qos: .userInitiated)

/// CameraScreen — 카메라 프리뷰 / shutter / new-site chip / 권한 분기를 한 화면에 통합.
///
/// 책임:
/// - `CameraScreenViewState.compute(...)` 결과로 UI 분기만 결정.
/// - shutter tap → `MediaCapture`를 생성/보관하고 `AVCapturePhotoOutput.capturePhoto`
///   호출. `@Sendable` callback에서 `Task { @MainActor in await handleCaptureResult(_:) }`
///   로 hop.
/// - 단일 캐논 핸들러 `handleCaptureResult`가 `defer`로 `isInFlight = false` + `mediaCapture = nil`
///   재설정 + `try result.get()` + `await mediaStorage.saveCapture(_:)`.
/// - 새 현장 chip tap → `await mediaStorage.markPendingNewSession()` + 상태 refresh.
/// - scenePhase 변화에 따라 `cameraSession.start()/stop()`을 **off-main** serial queue로
///   디스패치 (AVFoundation 권장).
///
/// 본 화면은 갤러리 / 디테일 네비게이션을 포함하지 않음 (Phase 3 이후).
struct CameraScreen: View {
    @EnvironmentObject private var deps: DependencyContainer
    @Environment(\.scenePhase) private var scenePhase

    @State private var cameraPermission: PermissionState = .notDetermined
    @State private var locationPermission: PermissionState = .notDetermined
    @State private var isPendingNewSession: Bool = false
    @State private var isInFlight: Bool = false
    @State private var captureError: String?
    @State private var mediaCapture: MediaCapture?

    var body: some View {
        let viewState = CameraScreenViewState.compute(
            camera: cameraPermission,
            location: locationPermission,
            isPending: isPendingNewSession,
            isInFlight: isInFlight
        )

        Group {
            switch viewState {
            case .cameraActive(let chip):
                activeView(chip: chip)
            case .permissionDenied(let target):
                deniedView(target: target)
            case .requestPrompt:
                requestView()
            case .cameraInitError(let reason):
                errorView(reason: reason)
            }
        }
        .task {
            await refreshPermissions()
            await refreshPending()
            handleScenePhase(scenePhase)
        }
        .onChange(of: scenePhase) { _, newPhase in
            Task { @MainActor in
                if newPhase == .active {
                    await refreshPermissions()
                    await refreshPending()
                }
                handleScenePhase(newPhase)
            }
        }
        .alert(
            "capture_error_title",
            isPresented: errorAlertBinding,
            presenting: captureError
        ) { _ in
            Button("button_ok", role: .cancel) { captureError = nil }
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Subviews

    @ViewBuilder
    private func activeView(chip: CameraScreenViewState.ChipState) -> some View {
        ZStack(alignment: .bottom) {
            CameraView(session: deps.cameraSession.session)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                newSiteChip(chip: chip)
                HStack(alignment: .center, spacing: 24) {
                    thumbnailPlaceholder
                    Spacer()
                    shutterButton(chip: chip)
                    Spacer()
                    Color.clear.frame(width: 56, height: 56)
                }
                .padding(.horizontal, 24)
            }
            .padding(.bottom, 32)
        }
    }

    private func newSiteChip(chip: CameraScreenViewState.ChipState) -> some View {
        Button {
            Task { await tapNewSite() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("camera_new_site_chip")
            }
            .font(.subheadline.weight(.semibold))
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial, in: Capsule())
            .overlay(
                Capsule()
                    .strokeBorder(chip == .pending ? Color.accentColor : Color.clear, lineWidth: 2)
            )
            .foregroundStyle(chip == .pending ? Color.accentColor : Color.primary)
        }
        .disabled(chip == .disabled)
        .opacity(chip == .disabled ? 0.6 : 1.0)
    }

    private var thumbnailPlaceholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.secondary.opacity(0.3))
            .frame(width: 56, height: 56)
    }

    private func shutterButton(chip: CameraScreenViewState.ChipState) -> some View {
        Button(action: tapShutter) {
            Circle()
                .strokeBorder(Color.white, lineWidth: 4)
                .frame(width: 80, height: 80)
                .overlay(
                    Circle()
                        .fill(chip == .disabled ? Color.secondary : Color.white)
                        .padding(10)
                )
        }
        .disabled(chip == .disabled)
        .accessibilityLabel(Text("camera_shutter_a11y"))
    }

    @ViewBuilder
    private func deniedView(target: CameraScreenViewState.PermissionTarget) -> some View {
        VStack(spacing: 16) {
            Image(systemName: deniedIconName(for: target))
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text(deniedTitleKey(for: target))
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(deniedDescriptionKey(for: target))
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .appBackgroundShield()
    }

    /// LocalizedStringKey를 반환해 `Text(_:)`가 verbatim String이 아닌
    /// localized key로 해석하도록 보장. 삼항 연산자 안에서 `String` literal
    /// 추론이 일어나면 .xcstrings 매칭이 실패할 수 있어 switch + 명시 타입 사용.
    private func deniedTitleKey(for target: CameraScreenViewState.PermissionTarget) -> LocalizedStringKey {
        switch target {
        case .camera: return "camera_permission_denied_title"
        case .location: return "location_permission_denied_title"
        }
    }

    private func deniedDescriptionKey(for target: CameraScreenViewState.PermissionTarget) -> LocalizedStringKey {
        switch target {
        case .camera: return "camera_permission_denied_description"
        case .location: return "location_permission_denied_description"
        }
    }

    private func deniedIconName(for target: CameraScreenViewState.PermissionTarget) -> String {
        switch target {
        case .camera: return "camera.fill"
        case .location: return "location.fill"
        }
    }

    @ViewBuilder
    private func requestView() -> some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.metering.center.weighted")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("camera_permission_request_title")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text("camera_permission_request_description")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
            Button {
                Task { await requestMissingPermissions() }
            } label: {
                Text("camera_permission_request_button")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .appBackgroundShield()
    }

    @ViewBuilder
    private func errorView(reason: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("camera_init_error_title")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)
            Text(reason)
                .font(.caption.monospaced())
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .lineLimit(3)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .appBackgroundShield()
    }

    // MARK: - Permission helpers

    @MainActor
    private func refreshPermissions() async {
        cameraPermission = deps.permissionsService.cameraState()
        locationPermission = deps.permissionsService.locationState()
    }

    @MainActor
    private func refreshPending() async {
        isPendingNewSession = await deps.mediaStorage.isPendingNewSession()
    }

    @MainActor
    private func requestMissingPermissions() async {
        if cameraPermission == .notDetermined {
            cameraPermission = await deps.permissionsService.requestCamera()
        }
        if locationPermission == .notDetermined {
            locationPermission = await deps.permissionsService.requestLocation()
        }
        // 새로 granted된 경우 즉시 location updates 시작 — scenePhase 변화를 기다리지 않음.
        startLocationUpdatesIfPermitted()
    }

    // MARK: - Capture flow

    private func tapShutter() {
        guard !isInFlight else { return }
        isInFlight = true
        let capture = MediaCapture(locationService: deps.locationService) { result in
            Task { @MainActor in
                await handleCaptureResult(result)
            }
        }
        mediaCapture = capture
        capture.capture(with: deps.cameraSession.photoOutput)
    }

    @MainActor
    private func handleCaptureResult(_ result: Result<PhotoCapturePayload, Error>) async {
        defer {
            isInFlight = false
            mediaCapture = nil
        }
        do {
            let payload = try result.get()
            _ = try await deps.mediaStorage.saveCapture(payload)
            await refreshPending()
        } catch {
            captureError = String(describing: error)
        }
    }

    @MainActor
    private func tapNewSite() async {
        guard !isInFlight else { return }
        await deps.mediaStorage.markPendingNewSession()
        await refreshPending()
    }

    // MARK: - ScenePhase

    @MainActor
    private func handleScenePhase(_ phase: ScenePhase) {
        let viewState = CameraScreenViewState.compute(
            camera: cameraPermission,
            location: locationPermission,
            isPending: isPendingNewSession,
            isInFlight: isInFlight
        )
        let cameraSession = deps.cameraSession

        switch phase {
        case .active:
            if case .cameraActive = viewState {
                cameraSessionQueue.async {
                    cameraSession.start()
                }
            }
            // 위치 업데이트는 권한이 granted일 때만 — 거부 상태에서는 noop 호출도 피함.
            startLocationUpdatesIfPermitted()
        case .background, .inactive:
            cameraSessionQueue.async {
                cameraSession.stop()
            }
            deps.locationService.stopUpdates()
        @unknown default:
            break
        }
    }

    /// 위치 권한이 granted일 때만 LocationService.startUpdates() 호출. denied/restricted/
    /// notDetermined 상태에서는 noop — MediaCapture.latestKnown()이 nil을 반환해도 ADR
    /// 흐름상 정상 (사진은 위치 없이 저장).
    @MainActor
    private func startLocationUpdatesIfPermitted() {
        guard locationPermission == .granted else { return }
        deps.locationService.startUpdates()
    }

    // MARK: - Alert binding

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { captureError != nil },
            set: { newValue in
                if !newValue { captureError = nil }
            }
        )
    }
}
