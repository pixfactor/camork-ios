import Foundation
import SwiftUI

enum SessionDateFilter: Equatable, Sendable {
    case all
    case today
    case thisWeek
    case thisMonth
    case custom(start: Date, end: Date)

    func contains(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        switch self {
        case .all:
            return true
        case .today:
            return calendar.isDate(date, inSameDayAs: now)
        case .thisWeek:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: now) else { return true }
            return interval.contains(date)
        case .thisMonth:
            guard let interval = calendar.dateInterval(of: .month, for: now) else { return true }
            return interval.contains(date)
        case .custom(let start, let end):
            let lower = calendar.startOfDay(for: min(start, end))
            let upperStart = calendar.startOfDay(for: max(start, end))
            guard let upper = calendar.date(byAdding: .day, value: 1, to: upperStart) else {
                return date >= lower
            }
            return date >= lower && date < upper
        }
    }
}
