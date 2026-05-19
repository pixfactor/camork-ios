import Foundation
import SwiftUI

/// App root에서 1회 생성되어 SwiftUI Environment로 전파되는 단일 컨테이너.
/// Singleton 금지 (ADR #9 의존성 주입) — `CamorkApp`의 Bootstrap 흐름이 본 컨테이너를
/// 1회 생성한 뒤 RootTabView에 `.environmentObject(_:)`로 주입.
///
/// 초기화 흐름:
/// 1. `Library/Application Support/Camork/` 루트 1회 계산 — DB와 MediaFileSystem이 공유.
/// 2. `CamorkDatabase.open()` — Metadata/camork.sqlite 열기 + migration v1.
/// 3. `MediaFileSystem(root: appRoot)` — Camork/Media + .staging + Thumbnails 부트스트랩.
/// 4. `MediaStorage(db:fs:)` — 단일 capture-save writer actor.
/// 5. `LocationService()`, `PermissionsService()`.
/// 6. `CameraSession(configuration: builder.makeConfiguration())` — 시뮬레이터에 카메라가
///    없으면 `.noDevice`로 throw하여 본 init도 throw. `CamorkApp.Bootstrap.failed`로
///    분기되어 `StorageInitErrorView`가 표시된다 (Phase 2c.1 임시 처리, 추후 카메라 선택적
///    개선 검토).
@MainActor
final class DependencyContainer: ObservableObject {
    let mediaStorage: MediaStorage
    let locationService: LocationService
    let permissionsService: PermissionsService
    let cameraSession: CameraSession

    init() throws {
        let appRoot = try Self.appRoot()
        let db = try CamorkDatabase.open()
        let fs = try MediaFileSystem(root: appRoot)
        self.mediaStorage = MediaStorage(db: db, fs: fs)
        self.locationService = LocationService()
        self.permissionsService = PermissionsService()

        let cameraConfig = CameraSessionBuilder.makeConfiguration()
        self.cameraSession = try CameraSession(configuration: cameraConfig)
    }

    /// `Library/Application Support/Camork/` — DB(Metadata/), MediaFileSystem(Media/,
    /// .staging/, Thumbnails/)가 공유하는 루트. 한 번만 계산되어 두 컴포넌트에 일관 적용.
    private static func appRoot() throws -> URL {
        let appSupport = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return appSupport.appendingPathComponent("Camork", isDirectory: true)
    }
}
