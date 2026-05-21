import SwiftUI

@main
struct CamorkApp: App {
    @State private var bootstrap: Bootstrap = .pending

    /// Bootstrap 상태 머신 (ADR #9 — `try!` 금지, safe 분기).
    /// - pending: 초기화 시도 중 (`.task`로 `load()` 호출).
    /// - ready: DependencyContainer 생성 성공 → RootTabView를 environmentObject로 주입.
    /// - failed: 초기화 실패 → `StorageInitErrorView` retry-able UI.
    enum Bootstrap {
        case pending
        case ready(DependencyContainer)
        case failed(Error)
    }

    var body: some Scene {
        WindowGroup {
            switch bootstrap {
            case .pending:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .appBackgroundShield()
                    .task { await load() }

            case .ready(let deps):
                RootTabView()
                    .environmentObject(deps)

            case .failed(let error):
                StorageInitErrorView(error: error) {
                    bootstrap = .pending
                }
            }
        }
    }

    @MainActor
    private func load() async {
        do {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--camork-preview-stub") {
                bootstrap = .ready(DependencyContainer.previewStub())
                return
            }
            #endif
            bootstrap = .ready(try DependencyContainer())
        } catch {
            bootstrap = .failed(error)
        }
    }
}
