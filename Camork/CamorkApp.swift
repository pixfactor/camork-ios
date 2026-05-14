import SwiftUI
import SwiftData

@main
struct CamorkApp: App {
    @StateObject private var authManager = AuthenticationManager.shared
    let modelContainer: ModelContainer

    init() {
        do {
            let schema = Schema([Folder.self, MediaItem.self])
            let modelConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: false
            )
            modelContainer = try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("ModelContainer 초기화 실패: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .appLock()
                .environmentObject(authManager)
        }
        .modelContainer(modelContainer)
    }
}
