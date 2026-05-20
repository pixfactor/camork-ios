import Testing
import Foundation
@testable import Camork

@Suite("AppLockController")
struct AppLockControllerTests {

    // MARK: - Init

    @Test("init: 저장된 policy가 없으면 immediate, 그리고 startLocked=true면 isLocked")
    func defaultsToImmediate() async throws {
        let defaults = makeDefaults()
        let controller = AppLockController(userDefaults: defaults, startLocked: true)

        #expect(await controller.policy == .immediate)
        #expect(await controller.isLocked == true)
    }

    @Test("init: 저장된 policy를 그대로 로드")
    func loadsPersistedPolicy() async throws {
        let defaults = makeDefaults()
        defaults.set(AppLockPolicy.fiveMinutes.rawValue, forKey: AppLockController.policyDefaultsKey)

        let controller = AppLockController(userDefaults: defaults, startLocked: true)

        #expect(await controller.policy == .fiveMinutes)
        #expect(await controller.isLocked == true)
    }

    @Test("init: policy가 .off면 startLocked=true여도 isLocked=false")
    func offPolicyDoesNotStartLocked() async throws {
        let defaults = makeDefaults()
        defaults.set(AppLockPolicy.off.rawValue, forKey: AppLockController.policyDefaultsKey)

        let controller = AppLockController(userDefaults: defaults, startLocked: true)

        #expect(await controller.isLocked == false)
    }

    @Test("init: startLocked=false면 어떤 policy든 isLocked=false (테스트 결정성)")
    func startLockedFalseOverrides() async throws {
        let defaults = makeDefaults()
        defaults.set(AppLockPolicy.immediate.rawValue, forKey: AppLockController.policyDefaultsKey)

        let controller = AppLockController(userDefaults: defaults, startLocked: false)

        #expect(await controller.isLocked == false)
    }

    // MARK: - setPolicy

    @Test("setPolicy: 새 policy를 UserDefaults에 영속")
    func setPolicyPersists() async throws {
        let defaults = makeDefaults()
        let controller = AppLockController(userDefaults: defaults, startLocked: false)

        await controller.setPolicy(.fifteenMinutes)

        #expect(await controller.policy == .fifteenMinutes)
        #expect(defaults.string(forKey: AppLockController.policyDefaultsKey) == AppLockPolicy.fifteenMinutes.rawValue)
    }

    @Test("setPolicy(.off): 즉시 isLocked=false + background timestamp clear")
    func setPolicyOffUnlocks() async throws {
        let defaults = makeDefaults()
        let controller = AppLockController(userDefaults: defaults, startLocked: true)
        await controller.didEnterBackground(at: Date(timeIntervalSince1970: 1_000))

        await controller.setPolicy(.off)

        #expect(await controller.isLocked == false)
        // .off로 바꾼 직후엔 active로 돌아와도 lock 안 됨
        let lockedAfter = await controller.didBecomeActive(at: Date(timeIntervalSince1970: 100_000))
        #expect(lockedAfter == false)
    }

    // MARK: - Background → Active transitions

    @Test(".immediate: 어떤 background 진입이든 다음 active 복귀에서 잠금")
    func immediateAlwaysLocks() async throws {
        let controller = makeController(policy: .immediate, startLocked: false)

        await controller.didEnterBackground(at: Date(timeIntervalSince1970: 1_000))
        let locked = await controller.didBecomeActive(at: Date(timeIntervalSince1970: 1_000.5))

        #expect(locked == true)
        #expect(await controller.isLocked == true)
    }

    @Test(".oneMinute: 59s 경과는 unlock 유지, 60s 이상은 lock")
    func oneMinuteThreshold() async throws {
        let c1 = makeController(policy: .oneMinute, startLocked: false)
        await c1.didEnterBackground(at: Date(timeIntervalSince1970: 1_000))
        let locked59 = await c1.didBecomeActive(at: Date(timeIntervalSince1970: 1_059))
        #expect(locked59 == false)
        #expect(await c1.isLocked == false)

        let c2 = makeController(policy: .oneMinute, startLocked: false)
        await c2.didEnterBackground(at: Date(timeIntervalSince1970: 1_000))
        let locked60 = await c2.didBecomeActive(at: Date(timeIntervalSince1970: 1_060))
        #expect(locked60 == true)
        #expect(await c2.isLocked == true)
    }

    @Test(".fiveMinutes / .fifteenMinutes 경계")
    func longerThresholds() async throws {
        let c5 = makeController(policy: .fiveMinutes, startLocked: false)
        await c5.didEnterBackground(at: Date(timeIntervalSince1970: 0))
        #expect(await c5.didBecomeActive(at: Date(timeIntervalSince1970: 299)) == false)

        let c5b = makeController(policy: .fiveMinutes, startLocked: false)
        await c5b.didEnterBackground(at: Date(timeIntervalSince1970: 0))
        #expect(await c5b.didBecomeActive(at: Date(timeIntervalSince1970: 300)) == true)

        let c15 = makeController(policy: .fifteenMinutes, startLocked: false)
        await c15.didEnterBackground(at: Date(timeIntervalSince1970: 0))
        #expect(await c15.didBecomeActive(at: Date(timeIntervalSince1970: 899)) == false)
        let c15b = makeController(policy: .fifteenMinutes, startLocked: false)
        await c15b.didEnterBackground(at: Date(timeIntervalSince1970: 0))
        #expect(await c15b.didBecomeActive(at: Date(timeIntervalSince1970: 900)) == true)
    }

    @Test(".off: background → active 어떤 시점에서도 isLocked=false 유지")
    func offNeverLocks() async throws {
        let controller = makeController(policy: .off, startLocked: false)

        await controller.didEnterBackground(at: Date(timeIntervalSince1970: 1_000))
        let locked = await controller.didBecomeActive(at: Date(timeIntervalSince1970: 100_000))

        #expect(locked == false)
        #expect(await controller.isLocked == false)
    }

    @Test("background timestamp 없이 active 복귀 → lock 트리거 안 함 (transient inactive→active 보호)")
    func missingBackgroundStampDoesNotLock() async throws {
        let controller = makeController(policy: .oneMinute, startLocked: false)

        let locked = await controller.didBecomeActive(at: Date(timeIntervalSince1970: 1_000))

        #expect(locked == false)
        #expect(await controller.isLocked == false)
    }

    @Test("이미 isLocked=true면 didBecomeActive는 잠금 유지 (unlock 별도)")
    func alreadyLockedStaysLocked() async throws {
        let controller = makeController(policy: .oneMinute, startLocked: true)
        await controller.didEnterBackground(at: Date(timeIntervalSince1970: 1_000))

        let locked = await controller.didBecomeActive(at: Date(timeIntervalSince1970: 1_001))

        #expect(locked == true)
    }

    // MARK: - unlock()

    @Test("unlock(): isLocked=false + background timestamp clear, 다음 active까지는 lock 안 됨")
    func unlockClearsStateAndDoesNotReLockWithoutBackground() async throws {
        let controller = makeController(policy: .immediate, startLocked: true)
        await controller.didEnterBackground(at: Date(timeIntervalSince1970: 1_000))

        await controller.unlock()

        #expect(await controller.isLocked == false)
        // unlock 직후 background 거치지 않고 active 들어와도 재잠금 금지 (Face ID prompt 등이
        // 만드는 active→inactive→active 루프 차단 — Plan E E3.b).
        let lockedAfter = await controller.didBecomeActive(at: Date(timeIntervalSince1970: 2_000))
        #expect(lockedAfter == false)
        #expect(await controller.isLocked == false)
    }

    @Test("unlock → background → active 정상 cycle은 grace 정책대로 다시 lock")
    func unlockThenBackgroundLocksByPolicy() async throws {
        let controller = makeController(policy: .immediate, startLocked: true)
        await controller.unlock()
        await controller.didEnterBackground(at: Date(timeIntervalSince1970: 1_000))

        let locked = await controller.didBecomeActive(at: Date(timeIntervalSince1970: 1_000.5))

        #expect(locked == true)
    }
}

// MARK: - Helpers

private func makeDefaults() -> UserDefaults {
    let suite = UserDefaults(suiteName: "AppLockControllerTests.\(UUID().uuidString)")!
    suite.removePersistentDomain(forName: "AppLockControllerTests")
    return suite
}

private func makeController(policy: AppLockPolicy, startLocked: Bool) -> AppLockController {
    let defaults = makeDefaults()
    defaults.set(policy.rawValue, forKey: AppLockController.policyDefaultsKey)
    return AppLockController(userDefaults: defaults, startLocked: startLocked)
}
