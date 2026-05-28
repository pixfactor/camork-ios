import Foundation

struct CloudSyncConfiguration: Sendable {
    let containerIdentifier: String
    let isFeatureVisible: Bool

    static var production: CloudSyncConfiguration {
        CloudSyncConfiguration(
            containerIdentifier: "iCloud.com.camork.app",
            isFeatureVisible: Bundle.main.object(forInfoDictionaryKey: "CAMORKCloudSyncFeatureVisible") as? Bool ?? false
        )
    }
}

enum CloudSyncAccountState: Sendable, Equatable {
    case available
    case noAccount
    case restricted
    case couldNotDetermine
    case temporarilyUnavailable
}

enum CloudSyncStatus: Sendable, Equatable {
    case disabled
    case checkingAccount
    case ready(CloudSyncAccountState)
    case syncing
    case synced(CloudSyncSummary)
    case restoring
    case restored(CloudRestoreSummary)
    case failed(String)
}

struct CloudSyncSummary: Sendable, Equatable {
    let syncedAt: Date
    let sessionCount: Int
    let photoCount: Int
}

struct CloudRestoreSummary: Sendable, Equatable {
    let restoredAt: Date
    let sessionCount: Int
    let photoCount: Int
    let assetCount: Int
}
