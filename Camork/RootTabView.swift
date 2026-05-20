import SwiftUI

/// 앱 root 탭 컨테이너. `CamorkApp.Bootstrap.ready`에서 `DependencyContainer`를
/// `.environmentObject(_:)`로 받아 자식 화면에 전파.
///
/// 카메라 탭은 `CameraScreen`, 갤러리 탭은 `GalleryScreen`, 설정은 placeholder를 유지 —
/// 설정은 Plan E에서 교체.
///
/// #Preview 제거: `CameraScreen`이 `@EnvironmentObject DependencyContainer`를 요구
/// 하지만 preview에서 안전하게 주입할 가벼운 deps stub / test seam이 아직 없다 (실제
/// `DependencyContainer.init()`은 GRDB/MediaFileSystem/CameraSession 등 실제 리소스를
/// 잡으므로 preview 환경에서 부적합). 본 RootTabView preview는 stub이 도입될 때까지
/// 보류. `SettingsPlaceholderView`는 deps 의존이 없어 자체 #Preview를 유지.
struct RootTabView: View {
    var body: some View {
        TabView {
            CameraScreen()
                .tabItem { Label("camera_tab_label", systemImage: "camera") }

            GalleryScreen()
                .tabItem { Label("gallery_tab_label", systemImage: "square.grid.2x2") }

            SettingsScreen()
                .tabItem { Label("settings_tab_label", systemImage: "gearshape") }
        }
        .appBackgroundShield()
    }
}
