import SwiftUI
import CryptoKit

struct FolderPasswordView: View {
    let folder: Folder
    var onUnlock: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var pin = ""
    @State private var failedAttempts = 0
    @State private var showError = false
    @State private var isLockedOut = false
    @State private var lockoutSeconds = 30

    private let maxPinLength = 4
    private let maxAttempts = 3
    private let lockoutDuration = 30

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()

                // Lock icon & title
                VStack(spacing: 16) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.orange)

                    Text("잠긴 폴더")
                        .font(.title2)
                        .fontWeight(.semibold)

                    Text("비밀번호를 입력하세요")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer().frame(height: 40)

                // PIN indicator dots
                HStack(spacing: 20) {
                    ForEach(0..<maxPinLength, id: \.self) { index in
                        Circle()
                            .fill(index < pin.count ? Color.accentColor : Color(.systemGray4))
                            .frame(width: 16, height: 16)
                            .animation(.easeInOut(duration: 0.15), value: pin.count)
                    }
                }

                // Error / lockout message
                if showError || isLockedOut {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(.top, 12)
                        .transition(.opacity)
                }

                Spacer()

                // Numeric keypad
                keypad
                    .padding(.bottom, 20)

                // Cancel button
                Button("취소") {
                    dismiss()
                }
                .foregroundStyle(.secondary)
                .padding(.bottom, 30)
            }
            .navigationBarHidden(true)
            .interactiveDismissDisabled()
        }
    }

    private var statusMessage: String {
        if isLockedOut {
            return "너무 많이 실패했습니다. \(lockoutSeconds)초 후에 다시 시도하세요."
        }
        if failedAttempts > 0 {
            return "비밀번호가 틀렸습니다. (\(failedAttempts)/\(maxAttempts))"
        }
        return ""
    }

    // MARK: - Keypad

    private var keypad: some View {
        VStack(spacing: 1) {
            let rows: [[String]] = [
                ["1", "2", "3"],
                ["4", "5", "6"],
                ["7", "8", "9"],
                ["", "0", "delete"]
            ]

            ForEach(rows, id: \.self) { row in
                HStack(spacing: 1) {
                    ForEach(row, id: \.self) { key in
                        keypadButton(for: key)
                    }
                }
            }
        }
        .frame(maxWidth: 280)
    }

    private func keypadButton(for key: String) -> some View {
        let isDisabled = isLockedOut
        return Button {
            handleKeypadInput(key)
        } label: {
            Group {
                if key == "delete" {
                    Image(systemName: "delete.left")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                } else if key.isEmpty {
                    Color.clear
                } else {
                    Text(key)
                        .font(.title)
                        .fontWeight(.medium)
                        .foregroundStyle(.primary)
                }
            }
            .frame(width: 80, height: 64)
            .background(
                key.isEmpty ? Color.clear : Color(.systemGray6)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .disabled(isDisabled && key != "")
        .buttonStyle(.plain)
    }

    private func handleKeypadInput(_ key: String) {
        guard !isLockedOut else { return }

        if key == "delete" {
            if !pin.isEmpty {
                pin.removeLast()
            }
            return
        }

        guard pin.count < maxPinLength else { return }
        pin.append(key)

        if pin.count == maxPinLength {
            verifyPin()
        }
    }

    // MARK: - Verification

    private func verifyPin() {
        guard let storedHash = folder.passwordHash else {
            // No password set — shouldn't happen, but unlock anyway
            onUnlock()
            return
        }

        let inputHash = hashPin(pin)

        if inputHash == storedHash {
            // Success
            onUnlock()
        } else {
            // Failure
            failedAttempts += 1
            withAnimation {
                showError = true
            }

            // Shake indicator
            pin = ""

            if failedAttempts >= maxAttempts {
                isLockedOut = true
                lockoutSeconds = lockoutDuration
                startLockoutTimer()
            }
        }
    }

    private func hashPin(_ pin: String) -> String {
        SHA256.hash(data: Data(pin.utf8))
            .compactMap { String(format: "%02x", $0) }
            .joined()
    }

    private func startLockoutTimer() {
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
            if lockoutSeconds > 1 {
                lockoutSeconds -= 1
            } else {
                timer.invalidate()
                isLockedOut = false
                failedAttempts = 0
                showError = false
                lockoutSeconds = lockoutDuration
            }
        }
    }
}
