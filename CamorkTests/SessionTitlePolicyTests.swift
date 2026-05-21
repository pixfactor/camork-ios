import Foundation
import Testing
@testable import Camork

@Suite("SessionTitlePolicy")
struct SessionTitlePolicyTests {
    @Test("automaticName keeps the existing stored-name format with place")
    func automaticNameWithPlace() {
        let date = Date(timeIntervalSince1970: 0)

        #expect(SessionTitlePolicy.automaticName(at: date, placeName: "성수동") == "성수동 · 1970-01-01 09:00")
    }

    @Test("displayTitle collapses an automatic place title to the place only")
    func displayTitleForAutomaticPlaceName() {
        let date = Date(timeIntervalSince1970: 0)
        let location = LocationSnapshot(latitude: 37.5, longitude: 127.0, horizontalAccuracy: 10, placeName: "성수동")
        let session = Session(
            id: UUID(),
            name: SessionTitlePolicy.automaticName(at: date, placeName: location.placeName),
            createdAt: date,
            firstLocation: location
        )

        #expect(SessionTitlePolicy.displayTitle(for: session) == "성수동")
    }

    @Test("displayTitle uses a localized fallback for automatic time-only names")
    func displayTitleForAutomaticTimeOnlyName() {
        let date = Date(timeIntervalSince1970: 0)
        let session = Session(
            id: UUID(),
            name: SessionTitlePolicy.automaticName(at: date, placeName: nil),
            createdAt: date,
            firstLocation: nil
        )

        #expect(SessionTitlePolicy.displayTitle(for: session) == String(localized: "session_title_fallback"))
    }

    @Test("displayTitle preserves user-edited names")
    func displayTitlePreservesUserEditedName() {
        let date = Date(timeIntervalSince1970: 0)
        let session = Session(
            id: UUID(),
            name: "도산공원 야간 점검",
            createdAt: date,
            firstLocation: nil
        )

        #expect(SessionTitlePolicy.displayTitle(for: session) == "도산공원 야간 점검")
    }
}

