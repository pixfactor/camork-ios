import Foundation

/// 앱 잠금 정책 (master spec §4.5). UserDefaults에 String raw로 영속.
///
/// `.off`는 잠금 자체를 끔. 그 외는 background 진입 후 경과 시간이 `graceInterval`을
/// 넘어선 시점에서 앱이 다시 active로 돌아오면 잠금. `.immediate`는 grace 0이라
/// 어떤 background 진입이든 즉시 잠금.
public enum AppLockPolicy: String, Sendable, Equatable, CaseIterable {
    case off
    case immediate
    case oneMinute
    case fiveMinutes
    case fifteenMinutes

    /// background → active 사이 경과 허용치(초). nil이면 잠금이 비활성화된 상태(`.off`).
    public var graceInterval: TimeInterval? {
        switch self {
        case .off: return nil
        case .immediate: return 0
        case .oneMinute: return 60
        case .fiveMinutes: return 5 * 60
        case .fifteenMinutes: return 15 * 60
        }
    }
}

/// 앱 잠금 state machine (Plan E Batch E3.a — pure logic, no biometrics).
///
/// 책임:
/// - `policy`를 UserDefaults에 String으로 영속.
/// - `didEnterBackground` / `didBecomeActive`를 받아 lock 여부를 결정.
/// - `isLocked` 상태를 외부에 노출 (UI가 LockScreen overlay 여부 판단).
/// - 잠금 해제는 `unlock()` 호출. 인증은 E3.b 의 `Authenticator` 가 담당하며 본 actor는
///   불통.
///
/// 시작 동작: master spec §4.5 "앱 시작 시 / 백그라운드에서 N분 후 복귀 시 잠금" — `.off`가
/// 아니면 init 시점에 `isLocked = true`. `startLocked: false` 로 inject하면 테스트 결정성을
/// 확보하면서 같은 의미를 유지.
public actor AppLockController {
    /// UserDefaults key. `Locale` / `Calendar` 같이 외부에서 override 가능하게 두지 않는
    /// 이유: 정책은 device-local 단일 키.
    public static let policyDefaultsKey = "camork.appLock.policy"

    private let userDefaults: UserDefaults
    private(set) public var policy: AppLockPolicy
    private(set) public var isLocked: Bool
    private var lastBackgroundedAt: Date?

    public init(
        userDefaults: UserDefaults = .standard,
        startLocked: Bool = true
    ) {
        self.userDefaults = userDefaults
        let raw = userDefaults.string(forKey: Self.policyDefaultsKey)
        self.policy = raw.flatMap(AppLockPolicy.init(rawValue:)) ?? .immediate
        self.isLocked = startLocked && self.policy != .off
        self.lastBackgroundedAt = nil
    }

    /// 사용자가 Settings에서 정책을 바꾸면 호출. `.off`는 즉시 잠금 해제, 그 외는 lock
    /// 상태를 건드리지 않음 (사용자가 의도적으로 강한 정책을 선택했다면 다음 background
    /// 사이클에서 자연스럽게 잠금).
    public func setPolicy(_ newPolicy: AppLockPolicy) {
        policy = newPolicy
        userDefaults.set(newPolicy.rawValue, forKey: Self.policyDefaultsKey)
        if newPolicy == .off {
            isLocked = false
            lastBackgroundedAt = nil
        }
    }

    /// `ScenePhase == .background`로 진입한 시점을 기록. 다음 `didBecomeActive(at:)`에서
    /// elapsed 계산에 사용.
    public func didEnterBackground(at: Date) {
        lastBackgroundedAt = at
    }

    /// `ScenePhase == .active`로 복귀. policy의 grace를 넘었으면 `isLocked = true`로 set.
    /// 이미 잠긴 상태면 그대로 유지(unlock은 별도 호출). 반환값은 호출자가 UI 분기에
    /// 사용하도록 현재 lock 여부.
    @discardableResult
    public func didBecomeActive(at: Date) -> Bool {
        guard let grace = policy.graceInterval else {
            isLocked = false
            lastBackgroundedAt = nil
            return false
        }
        if isLocked {
            // 이미 잠겨 있으면 background timestamp는 의미 없음
            lastBackgroundedAt = nil
            return true
        }
        let elapsed = lastBackgroundedAt.map { at.timeIntervalSince($0) } ?? .infinity
        if elapsed >= grace {
            isLocked = true
        }
        lastBackgroundedAt = nil
        return isLocked
    }

    /// 인증 성공 시 호출. `Authenticator` (E3.b)가 LAContext 결과를 받아서 본 메서드
    /// 호출.
    public func unlock() {
        isLocked = false
        lastBackgroundedAt = nil
    }
}
