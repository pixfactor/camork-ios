@preconcurrency import CloudKit
import Foundation

actor CloudSyncController {
    enum Error: Swift.Error, Sendable, Equatable {
        case featureHidden
        case syncDisabled
        case accountUnavailable(CloudSyncAccountState)
        case assetReadFailed
    }

    private let mediaStorage: MediaStorage
    private let configuration: CloudSyncConfiguration
    private let makeContainer: @Sendable () -> CKContainer
    private let defaults: UserDefaults
    private let temporaryRoot: URL
    private let now: @Sendable () -> Date
    private let enabledKey = "CloudSync.isEnabled"

    init(
        mediaStorage: MediaStorage,
        configuration: CloudSyncConfiguration = .production,
        defaults: UserDefaults = .standard,
        temporaryRoot: URL = FileManager.default.temporaryDirectory,
        makeContainer: (@Sendable () -> CKContainer)? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.mediaStorage = mediaStorage
        self.configuration = configuration
        self.makeContainer = makeContainer ?? {
            CKContainer(identifier: configuration.containerIdentifier)
        }
        self.defaults = defaults
        self.temporaryRoot = temporaryRoot
        self.now = now
    }

    func featureVisible() -> Bool {
        configuration.isFeatureVisible
    }

    func isEnabled() -> Bool {
        defaults.bool(forKey: enabledKey)
    }

    func setEnabled(_ enabled: Bool) throws {
        guard configuration.isFeatureVisible else { throw Error.featureHidden }
        defaults.set(enabled, forKey: enabledKey)
    }

    func accountState() async -> CloudSyncAccountState {
        let container = makeContainer()
        return await withCheckedContinuation { continuation in
            container.accountStatus { status, _ in
                continuation.resume(returning: Self.mapAccountStatus(status))
            }
        }
    }

    func syncNow() async throws -> CloudSyncSummary {
        guard configuration.isFeatureVisible else { throw Error.featureHidden }
        guard isEnabled() else { throw Error.syncDisabled }
        let state = await accountState()
        guard state == .available else { throw Error.accountUnavailable(state) }

        let container = makeContainer()
        let rows = try await mediaStorage.fetchExportRows()
        let database = container.privateCloudDatabase
        let assetRoot = try makeAssetRoot()
        defer { try? FileManager.default.removeItem(at: assetRoot) }

        for session in rows.sessions {
            try await save(CloudRecordMapper.sessionRecord(from: session), in: database)
        }

        for photo in rows.photos {
            let assetURL = try await prepareAssetIfAvailable(for: photo, under: assetRoot)
            let record = try CloudRecordMapper.photoRecord(from: photo, originalAssetURL: assetURL)
            try await save(record, in: database)
        }

        return CloudSyncSummary(
            syncedAt: now(),
            sessionCount: rows.sessions.count,
            photoCount: rows.photos.count
        )
    }

    func restoreFromCloud() async throws -> CloudRestoreSummary {
        guard configuration.isFeatureVisible else { throw Error.featureHidden }
        guard isEnabled() else { throw Error.syncDisabled }
        let state = await accountState()
        guard state == .available else { throw Error.accountUnavailable(state) }

        let container = makeContainer()
        let database = container.privateCloudDatabase
        let sessionRecords = try await fetchRecords(type: CloudRecordMapper.RecordType.session, in: database)
        let photoRecords = try await fetchRecords(type: CloudRecordMapper.RecordType.photo, in: database)

        var restoredSessions = 0
        var restoredPhotos = 0
        var restoredAssets = 0

        for record in sessionRecords {
            let session = try CloudRecordMapper.session(from: record)
            try await mediaStorage.upsertCloudSession(session)
            restoredSessions += 1
        }

        for record in photoRecords {
            let photo = try CloudRecordMapper.photo(from: record)
            try await mediaStorage.upsertCloudPhotoMetadata(photo)
            restoredPhotos += 1

            if let assetURL = CloudRecordMapper.originalAssetURL(from: record) {
                let data = try Data(contentsOf: assetURL)
                if try await mediaStorage.restoreCloudPhotoData(id: photo.id, data: data) {
                    restoredAssets += 1
                }
            }
        }

        return CloudRestoreSummary(
            restoredAt: now(),
            sessionCount: restoredSessions,
            photoCount: restoredPhotos,
            assetCount: restoredAssets
        )
    }

    private static func mapAccountStatus(_ status: CKAccountStatus) -> CloudSyncAccountState {
        switch status {
        case .available:
            return .available
        case .noAccount:
            return .noAccount
        case .restricted:
            return .restricted
        case .couldNotDetermine:
            return .couldNotDetermine
        case .temporarilyUnavailable:
            return .temporarilyUnavailable
        @unknown default:
            return .couldNotDetermine
        }
    }

    private func save(_ record: CKRecord, in database: CKDatabase) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Swift.Error>) in
            let operation = CKModifyRecordsOperation(recordsToSave: [record])
            operation.savePolicy = .allKeys
            operation.modifyRecordsResultBlock = { result in
                continuation.resume(with: result)
            }
            database.add(operation)
        }
    }

    private func fetchRecords(type: String, in database: CKDatabase) async throws -> [CKRecord] {
        let query = CKQuery(recordType: type, predicate: NSPredicate(value: true))
        var records: [CKRecord] = []
        var page = try await fetchPage(query: query, in: database)
        try records.append(contentsOf: page.matchResults.map { try $0.1.get() })

        while let cursor = page.queryCursor {
            page = try await fetchPage(cursor: cursor, in: database)
            try records.append(contentsOf: page.matchResults.map { try $0.1.get() })
        }
        return records
    }

    private func fetchPage(
        query: CKQuery,
        in database: CKDatabase
    ) async throws -> (matchResults: [(CKRecord.ID, Result<CKRecord, any Swift.Error>)], queryCursor: CKQueryOperation.Cursor?) {
        try await withCheckedThrowingContinuation { continuation in
            database.fetch(withQuery: query, inZoneWith: nil) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func fetchPage(
        cursor: CKQueryOperation.Cursor,
        in database: CKDatabase
    ) async throws -> (matchResults: [(CKRecord.ID, Result<CKRecord, any Swift.Error>)], queryCursor: CKQueryOperation.Cursor?) {
        try await withCheckedThrowingContinuation { continuation in
            database.fetch(withCursor: cursor) { result in
                continuation.resume(with: result)
            }
        }
    }

    private func makeAssetRoot() throws -> URL {
        let root = temporaryRoot
            .appendingPathComponent("Camork", isDirectory: true)
            .appendingPathComponent("CloudSyncAssets", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func prepareAssetIfAvailable(for photo: Photo, under root: URL) async throws -> URL? {
        do {
            let data = try await mediaStorage.loadPhotoData(for: photo)
            let url = root.appendingPathComponent(photo.fileName)
            try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            return url
        } catch MediaStorage.Error.invalidFileName {
            throw Error.assetReadFailed
        } catch {
            return nil
        }
    }
}
