import SwiftUI

struct AppLockModifier: ViewModifier {
    @ObservedObject private var authManager = AuthenticationManager.shared
    @Environment(\.scenePhase) private var scenePhase
    @State private var showLockScreen = false

    func body(content: Content) -> some View {
        ZStack {
            content
                .blur(radius: showLockScreen ? 20 : 0)
                .disabled(showLockScreen)

            if showLockScreen {
                LockScreenView(authManager: authManager)
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: showLockScreen)
        .onChange(of: scenePhase) { _, newPhase in
            handleScenePhaseChange(newPhase)
        }
        .onChange(of: authManager.isUnlocked) { _, unlocked in
            if unlocked {
                withAnimation { showLockScreen = false }
            }
        }
    }

    private func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .background:
            if authManager.isLockEnabled {
                authManager.lock()
            }
        case .inactive:
            break
        case .active:
            if authManager.isLockEnabled && !authManager.isUnlocked {
                withAnimation { showLockScreen = true }
            }
        @unknown default:
            break
        }
    }
}

extension View {
    func appLock() -> some View {
        modifier(AppLockModifier())
    }
}
