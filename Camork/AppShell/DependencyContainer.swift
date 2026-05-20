import Foundation
import SwiftUI

/// App root에서 1회 생성되어 SwiftUI Environment로 전파되는 단일 컨테이너.
/// Singleton 금지 (ADR #9 의존성 주입) — `CamorkApp`의 Bootstrap 흐름이 본 컨테이너를
/// 1회 생성한 뒤 RootTabView에 `.environmentObject(_:)`로 주입.
///
/// 초기화 흐름:
/// 1. `Library/Application Support/Camork/` 루트 1회 계산 — media + DB metadata 영속.
/// 2. `Library/Caches/Camork/` 루트 1회 계산 — thumbnail 캐시 영속 (Plan C Phase 2.1).
///    iOS 자동 backup 제외 + 공간 부족 시 시스템이 자동 정리 (재생성 가능 자원).
/// 3. `CamorkDatabase.open()` — Metadata/camork.sqlite 열기 + migration v1.
/// 4. `MediaFileSystem(root: appRoot, cachesRoot: cachesRoot)` — Application Support
///    하위(Media/, .staging/, Thumbnails legacy) + Caches 하위(Thumbnails) 양쪽
///    부트스트랩. legacy Thumbnails는 Plan B 잔재 — Plan C 이후 사용처 없음
///    (cruft 정리는 후속 phase에서).
/// 5. `MediaStorage(db:fs:)` — 단일 capture-save writer actor.
/// 6. `SharePreparer(mediaStorage:)` — 공유용 sanitized temp copy 준비/정리 actor.
/// 7. `LocationService()`, `PermissionsService()`.
/// 8. `CameraSession(configuration: builder.makeConfiguration())` — 시뮬레이터에 카메라가
///    없으면 `.noDevice`로 throw하여 본 init도 throw. `CamorkApp.Bootstrap.failed`로
///    분기되어 `StorageInitErrorView`가 표시된다 (Phase 2c.1 임시 처리, 추후 카메라 선택적
///    개선 검토).
@MainActor
final class DependencyContainer: ObservableObject {
    let mediaStorage: MediaStorage
    let sharePreparer: SharePreparer
    let locationService: LocationService
    let permissionsService: PermissionsService
    let cameraSession: CameraSession
    /// Plan E Batch E4 — Settings 화면이 lock policy picker로 본 actor를 조작. E3.b가
    /// LockScreen overlay에서 `isLocked` 상태를 구독.
    let appLockController: AppLockController

    init() throws {
        let appRoot = try Self.appRoot()
        let cachesRoot = try Self.cachesRoot()
        let db = try CamorkDatabase.open()
        let fs = try MediaFileSystem(root: appRoot, cachesRoot: cachesRoot)
        let mediaStorage = MediaStorage(db: db, fs: fs)
        let sharePreparer = SharePreparer(mediaStorage: mediaStorage)
        self.mediaStorage = mediaStorage
        self.sharePreparer = sharePreparer
        self.locationService = LocationService()
        self.permissionsService = PermissionsService()
        self.appLockController = AppLockController()

        let cameraConfig = CameraSessionBuilder.makeConfiguration()
        self.cameraSession = try CameraSession(configuration: cameraConfig)

        Task {
            await sharePreparer.cleanupExpired()
        }

        // Plan E Batch E5 — 30일 자동 영구 삭제. 앱 시작 시 best-effort. BGTaskScheduler
        // 통합은 v1.1 이후. cutoff은 호출 시점 기준이며 결정성 / DI는 본 init 외부에서
        // 필요해질 때 분리.
        Task { [mediaStorage] in
            let cutoff = Date().addingTimeInterval(-30 * 24 * 60 * 60)
            _ = try? await mediaStorage.purgeExpired(cutoff: cutoff)
        }
    }

    /// `Library/Application Support/Camork/` — DB metadata와 primary media storage의 루트.
    /// DB(Metadata/camork.sqlite) + MediaFileSystem(Media/, Media/.staging/, 그리고 Plan B
    /// 잔재인 legacy Thumbnails/)를 보유. 실제 thumbnail cache는 본 루트가 아닌
    /// 아래 `cachesRoot()` (Library/Caches/Camork/) 아래에 저장 — Plan C Phase 2.1.
    private static func appRoot() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport.appendingPathComponent("Camork", isDirectory: true)
    }

    /// `Library/Caches/Camork/` — thumbnail 캐시 루트 (Plan C Phase 2.1). iOS가 자동
    /// backup 제외하므로 `isExcludedFromBackup` flag 불필요. 공간 부족 시 iOS가
    /// 자동 정리 — 재생성 가능 자원.
    private static func cachesRoot() throws -> URL {
        let caches = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return caches.appendingPathComponent("Camork", isDirectory: true)
    }
}
