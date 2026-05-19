import SwiftUI

struct RootTabView: View {
    var body: some View {
        TabView {
            CameraPlaceholderView()
                .tabItem { Label("camera_tab_label", systemImage: "camera") }

            GalleryPlaceholderView()
                .tabItem { Label("gallery_tab_label", systemImage: "square.grid.2x2") }

            SettingsPlaceholderView()
                .tabItem { Label("settings_tab_label", systemImage: "gearshape") }
        }
        .appBackgroundShield()
    }
}

#Preview("Dark") {
    RootTabView().preferredColorScheme(.dark)
}

#Preview("Light") {
    RootTabView().preferredColorScheme(.light)
}

#Preview("AX5") {
    RootTabView()
        .preferredColorScheme(.dark)
        .dynamicTypeSize(.accessibility5)
}
