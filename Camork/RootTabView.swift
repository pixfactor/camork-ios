import SwiftUI

/// 앱 root 탭 컨테이너. `CamorkApp.Bootstrap.ready`에서 `DependencyContainer`를
/// `.environmentObject(_:)`로 받아 자식 화면에 전파.
///
/// Plan E Batch E3.b 부터는 `AppLockController.isLocked`를 반영하는 `LockScreen` overlay를
/// `ZStack` 최상위에 둔다. scene phase 처리는 다음 두 view-local state로 결정성을 보장한다:
///
/// - `hasEnteredBackgroundSinceActive`: `.background`를 실제로 거친 active 복귀만 lock 판정
///   대상으로 인정. LAContext / Face ID prompt 자체가 만드는 `.active → .inactive → .active`
///   루프나 알림 배너로 인한 일시적 .inactive 통과는 lock을 트리거하지 않는다.
/// - `lastBackgroundedAt`: `.background` 시점에 View가 직접 캡쳐한 `Date`. `.active` 경로의
///   Task가 이 timestamp를 actor에 명시적으로 다시 박은 뒤 `didBecomeActive`를 호출 —
///   suspend된 unstructured background Task의 actor write가 active 판정보다 늦어져 stale
///   상태를 보는 race를 차단한다.
///
/// `#Preview` 제거 사유는 기존과 동일: `DependencyContainer.init()`이 GRDB / 카메라 등
/// 실제 리소스를 잡으므로 preview-safe stub seam이 도입되기 전까지 본 RootTabView preview를
/// 보류. 자체 #Preview가 가능한 자식 view (예: `SettingsPlaceholderView`)는 별도 보존.
struct RootTabView: View {
    @EnvironmentObject private var deps: DependencyContainer
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab: RootTab = RootTab.initialSelection
    @State private var isLocked: Bool = false
    @State private var showsGalleryChromeFade = false
    /// `.background` 진입을 거친 active 복귀일 때만 lock 판정을 트리거. LAContext / Face ID
    /// prompt 자체가 active → inactive → active를 만들어 이 플래그가 없으면 unlock 직후
    /// 즉시 재잠금 루프가 형성된다 (Plan E E3.b 사용자 critic).
    @State private var hasEnteredBackgroundSinceActive: Bool = false
    /// `.background` 진입 시점을 View-local에 저장해 두고 active Task가 actor에 직접 전달.
    /// 이전 구현은 background에서 unstructured `Task { ... }`로 actor 상태를 write했는데,
    /// suspend / active 복귀 순서에 따라 active 판정이 stale timestamp를 보게 될 수 있었다.
    /// 본 state로 ordering을 결정적으로 묶는다 (Plan E E3.b 추가 critic).
    @State private var lastBackgroundedAt: Date?

    var body: some View {
        ZStack {
            TabView(selection: $selectedTab) {
                CameraScreen()
                    .tabItem { Label("camera_tab_label", systemImage: "camera") }
                    .tag(RootTab.camera)

                GalleryScreen()
                    .tabItem { Label("gallery_tab_label", systemImage: "square.grid.2x2") }
                    .tag(RootTab.gallery)

                SettingsScreen()
                    .tabItem { Label("settings_tab_label", systemImage: "gearshape") }
                    .tag(RootTab.settings)
            }
            .onPreferenceChange(GalleryBottomChromeFadePreferenceKey.self) { showsGalleryChromeFade = $0 }
            .appBackgroundShield()
            // 잠금 상태에서는 탭 인터랙션을 차단 (visual은 overlay가 가리지만 hit-test도 막아 보안).
            .disabled(isLocked)

            if selectedTab == .gallery && showsGalleryChromeFade {
                bottomChromeFade
            }

            if isLocked {
                LockScreen(
                    onUnlocked: handleUnlocked,
                    authenticator: LAContextAuthenticator()
                )
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isLocked)
        .task {
            // 앱 cold start 시점 controller가 결정한 lock 상태를 동기화.
            isLocked = await deps.appLockController.isLocked
        }
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhase(newPhase)
        }
    }

    private func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .background:
            let now = Date()
            hasEnteredBackgroundSinceActive = true
            lastBackgroundedAt = now
            // actor에는 best-effort로 알리되, lock 판정은 active 경로에서 동일 timestamp로
            // 재기록해 결정성을 확보한다 (suspend 중 actor write가 늦어져도 active 판정이
            // stale 상태를 보지 않게).
            Task { await deps.appLockController.didEnterBackground(at: now) }
        case .active:
            // background → active 전환에서만 lock 판정. .inactive 단독 통과(Face ID prompt,
            // 알림 배너 등)는 무시 — 같은 foreground session에서의 재잠금 루프 차단.
            guard hasEnteredBackgroundSinceActive, let backgroundedAt = lastBackgroundedAt else {
                return
            }
            hasEnteredBackgroundSinceActive = false
            lastBackgroundedAt = nil
            let now = Date()
            Task {
                // background Task가 suspend되어 actor 상태가 비어있을 가능성에 대비해 active
                // 경로에서 timestamp를 한 번 더 박은 뒤 판정. didEnterBackground는 idempotent.
                await deps.appLockController.didEnterBackground(at: backgroundedAt)
                let locked = await deps.appLockController.didBecomeActive(at: now)
                await MainActor.run { isLocked = locked }
            }
        case .inactive:
            break
        @unknown default:
            break
        }
    }

    private func handleUnlocked() {
        Task {
            await deps.appLockController.unlock()
            await MainActor.run { isLocked = false }
        }
    }

    /// Visual-only fade that lets gallery cards recede beneath the tab bar capsule.
    /// It lives at the tab root so it can extend into the bottom safe area.
    private var bottomChromeFade: some View {
        VStack(spacing: 0) {
            Spacer()
            LinearGradient(
                colors: [
                    Color.camorkBackground.opacity(0.65),
                    Color.camorkBackground.opacity(0)
                ],
                startPoint: .bottom,
                endPoint: .top
            )
            .frame(height: 144)
        }
        .ignoresSafeArea(edges: .bottom)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private enum RootTab: Hashable {
        case camera
        case gallery
        case settings

        static var initialSelection: RootTab {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--camork-start-gallery") {
                return .gallery
            }
            #endif
            return .camera
        }
    }
}
