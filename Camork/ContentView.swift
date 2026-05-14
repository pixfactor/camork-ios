import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            FolderListView()
                .tabItem {
                    Label("사진첩", systemImage: "photo.on.rectangle")
                }

            CameraContainerView()
                .tabItem {
                    Label("카메라", systemImage: "camera")
                }

            SearchView()
                .tabItem {
                    Label("검색", systemImage: "magnifyingglass")
                }

            SettingsView()
                .tabItem {
                    Label("설정", systemImage: "gearshape")
                }
        }
    }
}
