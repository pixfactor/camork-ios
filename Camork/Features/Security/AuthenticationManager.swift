import Foundation
import LocalAuthentication
import Combine

@MainActor
final class AuthenticationManager: ObservableObject {
    @Published var isUnlocked: Bool = false
    @Published var isLockEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isLockEnabled, forKey: "isAppLockEnabled")
            if !isLockEnabled {
                isUnlocked = true
            }
        }
    }

    static let shared = AuthenticationManager()

    private init() {
        self.isLockEnabled = UserDefaults.standard.bool(forKey: "isAppLockEnabled")
        self.isUnlocked = !self.isLockEnabled
    }

    func authenticate() async -> Bool {
        guard isLockEnabled else {
            isUnlocked = true
            return true
        }

        let context = LAContext()
        context.localizedCancelTitle = "취소"

        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            // Device has no passcode or biometry — unlock by default
            isUnlocked = true
            return true
        }

        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Camork 잠금을 해제합니다."
            )
            isUnlocked = success
            return success
        } catch let laError as LAError {
            handleLAError(laError)
            return false
        } catch {
            return false
        }
    }

    func checkBiometryType() -> LABiometryType {
        let context = LAContext()
        var error: NSError?
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error)
        return context.biometryType
    }

    func lock() {
        guard isLockEnabled else { return }
        isUnlocked = false
    }

    private func handleLAError(_ error: LAError) {
        switch error.code {
        case .biometryNotAvailable:
            // Fall through to passcode (deviceOwnerAuthentication handles this)
            break
        case .biometryNotEnrolled:
            // No biometry enrolled — passcode fallback active
            break
        case .biometryLockout:
            // Biometry locked — passcode fallback active
            break
        case .userCancel, .systemCancel, .appCancel:
            // User cancelled — keep locked
            isUnlocked = false
        case .userFallback:
            // User chose passcode — already handled by deviceOwnerAuthentication
            break
        default:
            isUnlocked = false
        }
    }

    var biometryDisplayName: String {
        switch checkBiometryType() {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "생체 인증"
        }
    }
}
