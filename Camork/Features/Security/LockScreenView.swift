import SwiftUI
import UIKit
import LocalAuthentication

struct LockScreenView: View {
    @ObservedObject var authManager: AuthenticationManager
    @State private var isAuthenticating = false
    @State private var showError = false
    @State private var errorMessage = ""

    var body: some View {
        ZStack {
            // Blurred background
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()

            VStack(spacing: 32) {
                Spacer()

                // App icon & name
                VStack(spacing: 16) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 60))
                        .foregroundStyle(.primary)
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 20)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.1), radius: 10, y: 4)
                        )

                    Text("Camork")
                        .font(.largeTitle)
                        .fontWeight(.bold)

                    Text("앱이 잠겨 있습니다")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                // Auth button
                VStack(spacing: 16) {
                    Button {
                        Task { await triggerAuthentication() }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: biometryIcon)
                                .font(.title3)
                            Text(biometryButtonLabel)
                                .font(.headline)
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.accentColor)
                        )
                    }
                    .disabled(isAuthenticating)
                    .padding(.horizontal, 40)

                    if showError {
                        Text(errorMessage)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .transition(.opacity)
                    }
                }
                .padding(.bottom, 50)
            }
        }
        .task {
            // Auto-trigger on appear
            await triggerAuthentication()
        }
    }

    private var biometryIcon: String {
        switch authManager.checkBiometryType() {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        default: return "lock.open.fill"
        }
    }

    private var biometryButtonLabel: String {
        switch authManager.checkBiometryType() {
        case .faceID: return "Face ID로 잠금 해제"
        case .touchID: return "Touch ID로 잠금 해제"
        default: return "패스코드로 잠금 해제"
        }
    }

    private func triggerAuthentication() async {
        guard !isAuthenticating else { return }
        isAuthenticating = true
        showError = false

        let success = await authManager.authenticate()

        isAuthenticating = false
        if !success {
            withAnimation {
                errorMessage = "인증에 실패했습니다. 다시 시도하세요."
                showError = true
            }
        }
    }
}
