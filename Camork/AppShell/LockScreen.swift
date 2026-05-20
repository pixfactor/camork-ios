import SwiftUI

/// 앱 잠금 화면 (Plan E Batch E3.b — master spec §4.5).
///
/// 책임:
/// - `appear` 직후 자동으로 `Authenticator.authenticate`를 호출 (Face ID prompt).
/// - 사용자가 "잠금 해제" 버튼을 다시 누르면 재시도.
/// - 성공하면 `onUnlocked()` 호출 — caller가 `AppLockController.unlock` + state 갱신.
/// - 실패 / 취소 시 잠금 화면 유지하고 사용자가 재시도하도록 안내.
///
/// 보안 invariant: 본 view가 화면에 있는 동안 뒤의 컨텐츠는 보이지 않아야 한다. caller가
/// ZStack에서 본 view를 최상위에 배치하고 불투명 배경을 깔도록 한다.
struct LockScreen: View {
    let onUnlocked: () -> Void
    let authenticator: Authenticator

    @State private var isAuthenticating = false
    @State private var lastResult: AuthenticationResult?
    @State private var hasAutoAttempted = false

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 24) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 64, weight: .regular))
                    .foregroundStyle(.white)

                Text("lock_screen_title")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.white)

                Button {
                    Task { await tryUnlock() }
                } label: {
                    HStack(spacing: 8) {
                        if isAuthenticating {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Image(systemName: "faceid")
                        }
                        Text("lock_screen_unlock_button")
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
                .disabled(isAuthenticating)
                .accessibilityLabel(Text("lock_screen_unlock_button"))

                if case .failed = lastResult {
                    Text("lock_screen_failed")
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
            .padding()
        }
        .preferredColorScheme(.dark)
        .task {
            guard !hasAutoAttempted else { return }
            hasAutoAttempted = true
            await tryUnlock()
        }
    }

    @MainActor
    private func tryUnlock() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        defer { isAuthenticating = false }
        let result = await authenticator.authenticate(reason: localizedReason)
        lastResult = result
        if result == .success {
            onUnlocked()
        }
    }

    private var localizedReason: String {
        String(localized: "lock_screen_reason")
    }
}
