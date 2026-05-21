import Foundation

enum SessionTitlePolicy {
    static func automaticName(at date: Date, placeName: String?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        let dateStr = formatter.string(from: date)
        if let placeName, !placeName.isEmpty {
            return "\(placeName) · \(dateStr)"
        }
        return dateStr
    }

    static func displayTitle(for session: Session) -> String {
        guard session.name == automaticName(
            at: session.createdAt,
            placeName: session.firstLocation?.placeName
        ) else {
            return session.name
        }

        if let placeName = session.firstLocation?.placeName, !placeName.isEmpty {
            return placeName
        }
        return String(localized: "session_title_fallback")
    }
}
