import Foundation
import LocalAuthentication

/// 잠금 해제용 인증 abstraction (Plan E Batch E3.b).
///
/// 실 구현은 `LAContextAuthenticator` — `LAPolicy.deviceOwnerAuthentication`을 평가해 Face ID
/// → 패스코드 fallback. 테스트 / preview는 `ResultAuthenticator` 같은 stub으로 주입.
public protocol Authenticator: Sendable {
    func authenticate(reason: String) async -> AuthenticationResult
}

/// 인증 결과 3분기 (master spec §4.5 — "Face ID 실패/취소 시: 잠금 화면 유지").
public enum AuthenticationResult: Sendable, Equatable {
    case success
    case userCancelled
    case failed
}

/// production 구현. `LAContext`를 매 호출마다 새로 생성 — context lifecycle 공유를 피해
/// 동시성 / 재진입 race를 차단.
public struct LAContextAuthenticator: Authenticator {
    public init() {}

    public func authenticate(reason: String) async -> AuthenticationResult {
        await withCheckedContinuation { (continuation: CheckedContinuation<AuthenticationResult, Never>) in
            let context = LAContext()
            var canEvaluateError: NSError?
            let policy: LAPolicy = .deviceOwnerAuthentication  // biometric → 실패 시 패스코드
            guard context.canEvaluatePolicy(policy, error: &canEvaluateError) else {
                continuation.resume(returning: .failed)
                return
            }
            context.evaluatePolicy(policy, localizedReason: reason) { success, evalError in
                if success {
                    continuation.resume(returning: .success)
                } else if let laError = evalError as? LAError, laError.code == .userCancel {
                    continuation.resume(returning: .userCancelled)
                } else {
                    continuation.resume(returning: .failed)
                }
            }
        }
    }
}

/// 테스트 / preview용 stub. 생성 시 지정한 result를 그대로 반환.
public struct ResultAuthenticator: Authenticator {
    public let result: AuthenticationResult

    public init(result: AuthenticationResult) {
        self.result = result
    }

    public func authenticate(reason: String) async -> AuthenticationResult {
        result
    }
}
