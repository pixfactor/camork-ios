import Foundation

enum MemoTemplate: String, CaseIterable, Identifiable {
    case meeting = "미팅"
    case estimate = "견적"
    case defect = "하자"
    case done = "완료"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .meeting: return "person.2.fill"
        case .estimate: return "doc.text.fill"
        case .defect: return "exclamationmark.triangle.fill"
        case .done: return "checkmark.circle.fill"
        }
    }

    var defaultMemo: String {
        switch self {
        case .meeting: return "미팅"
        case .estimate: return "견적"
        case .defect: return "하자"
        case .done: return "완료"
        }
    }
}
