import Foundation

extension DateFormatter {
    static let sectionHeader: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월 d일 EEEE"
        return formatter
    }()

    static let timeOnly: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "a h:mm"
        return formatter
    }()

    static let watermark: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy.MM.dd HH:mm"
        return formatter
    }()
}

extension Date {
    func relativeDateString() -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) {
            return "오늘"
        } else if calendar.isDateInYesterday(self) {
            return "어제"
        } else {
            return DateFormatter.sectionHeader.string(from: self)
        }
    }
}
