@preconcurrency import CloudKit
import Foundation

enum CloudSyncErrorPresentation {
    enum Reason: Equatable {
        case featureHidden
        case syncDisabled
        case accountUnavailable(CloudSyncAccountState)
        case schemaUnavailable
        case notAuthenticated
        case networkUnavailable
        case quotaExceeded
        case conflict
        case temporarilyUnavailable
        case assetReadFailed
        case generic
    }

    static func reason(for error: any Swift.Error) -> Reason {
        if let controllerError = error as? CloudSyncController.Error {
            switch controllerError {
            case .featureHidden:
                return .featureHidden
            case .syncDisabled:
                return .syncDisabled
            case .accountUnavailable(let state):
                return .accountUnavailable(state)
            case .assetReadFailed:
                return .assetReadFailed
            }
        }

        guard let cloudError = error as? CKError else {
            return .generic
        }

        switch cloudError.code {
        case .unknownItem where isMissingRecordType(cloudError):
            return .schemaUnavailable
        case .notAuthenticated:
            return .notAuthenticated
        case .networkUnavailable, .networkFailure:
            return .networkUnavailable
        case .quotaExceeded:
            return .quotaExceeded
        case .serverRecordChanged:
            return .conflict
        case .serviceUnavailable, .requestRateLimited, .zoneBusy:
            return .temporarilyUnavailable
        default:
            return .generic
        }
    }

    static func message(for error: any Swift.Error) -> String {
        switch reason(for: error) {
        case .featureHidden:
            return String(localized: "settings_icloud_error_feature_hidden")
        case .syncDisabled:
            return String(localized: "settings_icloud_error_sync_disabled")
        case .accountUnavailable(let state):
            return accountUnavailableMessage(for: state)
        case .schemaUnavailable:
            return String(localized: "settings_icloud_error_schema_unavailable")
        case .notAuthenticated:
            return String(localized: "settings_icloud_error_not_authenticated")
        case .networkUnavailable:
            return String(localized: "settings_icloud_error_network")
        case .quotaExceeded:
            return String(localized: "settings_icloud_error_quota")
        case .conflict:
            return String(localized: "settings_icloud_error_conflict")
        case .temporarilyUnavailable:
            return String(localized: "settings_icloud_error_temporarily_unavailable")
        case .assetReadFailed:
            return String(localized: "settings_icloud_error_asset_read_failed")
        case .generic:
            return String(localized: "settings_icloud_error_generic")
        }
    }

    private static func isMissingRecordType(_ error: CKError) -> Bool {
        let text = [
            error.localizedDescription,
            String(describing: error),
            String(describing: error.userInfo)
        ]
        .joined(separator: "\n")
        .lowercased()

        return text.contains("did not find record type")
            || text.contains("cannot create new type")
    }

    private static func accountUnavailableMessage(for state: CloudSyncAccountState) -> String {
        switch state {
        case .available:
            return String(localized: "settings_icloud_status_ready")
        case .noAccount:
            return String(localized: "settings_icloud_status_no_account")
        case .restricted:
            return String(localized: "settings_icloud_status_restricted")
        case .couldNotDetermine:
            return String(localized: "settings_icloud_status_unknown")
        case .temporarilyUnavailable:
            return String(localized: "settings_icloud_status_temporarily_unavailable")
        }
    }
}
