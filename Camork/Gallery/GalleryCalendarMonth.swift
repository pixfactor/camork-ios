import Foundation

struct GalleryCalendarDay: Identifiable, Equatable {
    let date: Date
    let isInDisplayedMonth: Bool

    var id: Date { date }
}

enum GalleryCalendarMonth {
    static let cellCount = 42

    static func startOfMonth(for date: Date, calendar: Calendar = .current) -> Date {
        calendar.dateInterval(of: .month, for: date)?.start ?? calendar.startOfDay(for: date)
    }

    static func days(for month: Date, calendar: Calendar = .current) -> [GalleryCalendarDay] {
        let monthStart = startOfMonth(for: month, calendar: calendar)
        let firstWeekday = calendar.component(.weekday, from: monthStart)
        let leadingDays = (firstWeekday - calendar.firstWeekday + 7) % 7
        let gridStart = calendar.date(byAdding: .day, value: -leadingDays, to: monthStart) ?? monthStart

        return (0..<cellCount).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: gridStart) else {
                return nil
            }
            return GalleryCalendarDay(
                date: calendar.startOfDay(for: date),
                isInDisplayedMonth: calendar.isDate(date, equalTo: monthStart, toGranularity: .month)
            )
        }
    }

    static func recordedDays(
        in sessions: [SessionWithPreview],
        calendar: Calendar = .current
    ) -> Set<Date> {
        Set(
            sessions
                .filter { $0.preview.totalPhotoCount > 0 }
                .map { calendar.startOfDay(for: $0.session.createdAt) }
        )
    }

    static func orderedWeekdaySymbols(calendar: Calendar = .current) -> [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        let startIndex = max(calendar.firstWeekday - 1, 0)
        return Array(symbols[startIndex..<symbols.count]) + Array(symbols[0..<startIndex])
    }
}
