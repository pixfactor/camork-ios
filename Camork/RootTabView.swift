import SwiftUI

/// 앱 root 탭 컨테이너. `CamorkApp.Bootstrap.ready`에서 `DependencyContainer`를
/// `.environmentObject(_:)`로 받아 자식 화면에 전파.
///
/// Plan E Batch E3.b 부터는 `AppLockController.isLocked`를 반영하는 `LockScreen` overlay를
/// `ZStack` 최상위에 둔다. scene phase 추적은 background/inactive → active 전환에서만
/// `didBecomeActive(at:)`를 호출 — active → active 반복(예: 시스템 alert 후 복귀)에서
/// 의도치 않은 재잠금 루프가 발생하지 않도록 이전 phase를 기억.
///
/// `#Preview` 제거 사유는 기존과 동일: `DependencyContainer.init()`이 GRDB / 카메라 등
/// 실제 리소스를 잡으므로 preview-safe stub seam이 도입되기 전까지 본 RootTabView preview를
/// 보류. 자체 #Preview가 가능한 자식 view (예: `SettingsPlaceholderView`)는 별도 보존.
struct RootTabView: View {
    @EnvironmentObject private var deps: DependencyContainer
    @Environment(\.scenePhase) private var scenePhase

    @State private var isLocked: Bool = false
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
            TabView {
                CameraScreen()
                    .tabItem { Label("camera_tab_label", systemImage: "camera") }

                GalleryScreen()
                    .tabItem { Label("gallery_tab_label", systemImage: "square.grid.2x2") }

                SettingsScreen()
                    .tabItem { Label("settings_tab_label", systemImage: "gearshape") }
            }
            .appBackgroundShield()
            // 잠금 상태에서는 탭 인터랙션을 차단 (visual은 overlay가 가리지만 hit-test도 막아 보안).
            .disabled(isLocked)

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
}
