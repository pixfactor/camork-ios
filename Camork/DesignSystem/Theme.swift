import SwiftUI

/// 8pt 그리드 spacing 토큰. 모든 컴포넌트 padding/spacing은 이 값들 중 하나를 사용.
enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

/// Continuous corner radius 토큰. iOS는 continuous 코너가 표준.
enum CornerRadius {
    static let sm: CGFloat = 6
    static let md: CGFloat = 12
    static let lg: CGFloat = 16
    static let xl: CGFloat = 24
}
