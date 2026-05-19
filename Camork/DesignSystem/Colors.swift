import SwiftUI

extension Color {
    /// 앱 강조색 — Asset Catalog의 AccentColor를 자동 사용.
    static let camorkAccent = Color.accentColor

    /// 1차 배경 — 시스템 배경 (다크모드에서 검정 계열)
    static let camorkBackground = Color(.systemBackground)

    /// 2차 배경 — 카드/그룹 컨테이너
    static let camorkSecondaryBackground = Color(.secondarySystemBackground)

    /// 3차 배경 — 카드 내부 강조
    static let camorkTertiaryBackground = Color(.tertiarySystemBackground)

    /// 구분선
    static let camorkSeparator = Color(.separator)

    /// 칩/빈 영역 등 subtle fill
    static let camorkFill = Color(.systemFill)
}
