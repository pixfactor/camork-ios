import Foundation
import Testing
@testable import Camork

@Suite("SessionDateFilter")
struct SessionDateFilterTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        calendar.firstWeekday = 2
        return calendar
    }

    @Test("today uses the user's local calendar day")
    func todayUsesLocalDay() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let sameLocalDay = now.addingTimeInterval(60 * 60)
        let previousLocalDay = now.addingTimeInterval(-24 * 60 * 60)

        #expect(SessionDateFilter.today.contains(sameLocalDay, now: now, calendar: calendar))
        #expect(!SessionDateFilter.today.contains(previousLocalDay, now: now, calendar: calendar))
    }

    @Test("custom range is inclusive by whole local days regardless of argument order")
    func customRangeWholeDays() throws {
        let formatter = ISO8601DateFormatter()
        let start = try #require(formatter.date(from: "2026-05-20T12:00:00Z"))
        let end = try #require(formatter.date(from: "2026-05-22T01:00:00Z"))
        let included = try #require(formatter.date(from: "2026-05-22T14:30:00Z"))
        let excluded = try #require(formatter.date(from: "2026-05-23T16:00:00Z"))

        let filter = SessionDateFilter.custom(start: end, end: start)
        #expect(filter.contains(included, now: end, calendar: calendar))
        #expect(!filter.contains(excluded, now: end, calendar: calendar))
    }
}
