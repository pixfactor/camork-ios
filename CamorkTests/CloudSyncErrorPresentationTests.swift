import CloudKit
import Foundation
import Testing
@testable import Camork

@Suite("CloudSyncErrorPresentation")
struct CloudSyncErrorPresentationTests {
    @Test("missing production record type is classified without leaking raw diagnostics")
    func missingRecordTypePresentation() {
        let error = CKError(
            .unknownItem,
            userInfo: [NSLocalizedDescriptionKey: "Did not find record type: CamorkSession"]
        )

        #expect(CloudSyncErrorPresentation.reason(for: error) == .schemaUnavailable)
        #expect(!CloudSyncErrorPresentation.message(for: error).contains("CKError"))
        #expect(!CloudSyncErrorPresentation.message(for: error).contains("CamorkSession"))
    }

    @Test("network failures use retryable user-facing copy")
    func networkPresentation() {
        let error = CKError(.networkUnavailable)

        #expect(CloudSyncErrorPresentation.reason(for: error) == .networkUnavailable)
    }

    @Test("local controller errors preserve account state")
    func accountUnavailablePresentation() {
        let error = CloudSyncController.Error.accountUnavailable(.noAccount)

        #expect(CloudSyncErrorPresentation.reason(for: error) == .accountUnavailable(.noAccount))
    }
}
