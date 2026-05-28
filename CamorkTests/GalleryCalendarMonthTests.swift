import Foundation
import Testing
@testable import Camork

@Suite("GalleryCalendarMonth")
struct GalleryCalendarMonthTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Asia/Seoul")!
        calendar.firstWeekday = 1
        return calendar
    }

    @Test("month grid always returns six weeks")
    func monthGridHasStableCellCount() throws {
        let month = try #require(Self.formatter.date(from: "2026-05-15T12:00:00Z"))
        let days = GalleryCalendarMonth.days(for: month, calendar: calendar)

        #expect(days.count == GalleryCalendarMonth.cellCount)
        #expect(days.filter(\.isInDisplayedMonth).count == 31)
    }

    @Test("recorded days use local start of day and ignore empty sessions")
    func recordedDaysUseLocalDay() throws {
        let recordedAt = try #require(Self.formatter.date(from: "2026-05-27T14:30:00Z"))
        let emptyAt = try #require(Self.formatter.date(from: "2026-05-28T14:30:00Z"))
        let days = GalleryCalendarMonth.recordedDays(
            in: [
                makeSession(at: recordedAt, photoCount: 3),
                makeSession(at: emptyAt, photoCount: 0)
            ],
            calendar: calendar
        )

        #expect(days == [calendar.startOfDay(for: recordedAt)])
    }

    private static let formatter = ISO8601DateFormatter()

    private func makeSession(at date: Date, photoCount: Int) -> SessionWithPreview {
        let id = UUID()
        return SessionWithPreview(
            session: Session(
                id: id,
                name: "현장",
                note: nil,
                createdAt: date,
                endedAt: nil,
                firstLocation: nil,
                deletedAt: nil
            ),
            preview: SessionPreview(
                sessionId: id,
                totalPhotoCount: photoCount,
                previewPhotos: []
            )
        )
    }
}
