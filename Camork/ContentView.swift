import SwiftUI
import SwiftData

// 회사 컴 연동 테스트용 주석입니다.
struct ContentView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var modelContext

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
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                purgeExpiredItems()
            }
        }
    }

    private func purgeExpiredItems() {
        let cutoff = Calendar.current.date(byAdding: .day, value: -30, to: Date())!
        let descriptor = FetchDescriptor<MediaItem>(
            predicate: #Predicate { $0.isDeleted && $0.deletedAt != nil && $0.deletedAt! < cutoff }
        )
        guard let expired = try? modelContext.fetch(descriptor) else { return }
        for item in expired {
            Task {
                try? await FileStorageManager.shared.deleteMedia(fileName: item.fileName)
            }
            modelContext.delete(item)
        }
        try? modelContext.save()
    }
}
