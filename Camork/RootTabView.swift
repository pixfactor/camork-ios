import SwiftUI

/// 앱 root 탭 컨테이너. `CamorkApp.Bootstrap.ready`에서 `DependencyContainer`를
/// `.environmentObject(_:)`로 받아 자식 화면에 전파.
///
/// 카메라 탭은 `CameraScreen` (Phase 2c.4). 갤러리/설정은 placeholder를 유지 — 갤러리는
/// Plan C, 설정은 Plan E.
///
/// #Preview 제거: `CameraScreen`은 `@EnvironmentObject DependencyContainer`를 요구
/// 하므로 preview 환경에서 deps stub 없이 렌더하면 런타임 크래시. 화면별 preview는
/// `CameraScreen`/`GalleryPlaceholderView`/`SettingsPlaceholderView` 파일에서 개별 제공.
struct RootTabView: View {
    var body: some View {
        TabView {
            CameraScreen()
                .tabItem { Label("camera_tab_label", systemImage: "camera") }

            GalleryPlaceholderView()
                .tabItem { Label("gallery_tab_label", systemImage: "square.grid.2x2") }

            SettingsPlaceholderView()
                .tabItem { Label("settings_tab_label", systemImage: "gearshape") }
        }
        .appBackgroundShield()
    }
}
