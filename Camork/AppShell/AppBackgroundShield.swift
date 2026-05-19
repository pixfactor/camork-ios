import SwiftUI

/// 백그라운드 진입 시 컨텐츠를 가리는 modifier.
///
/// v1 Core 에서는 placeholder. Plan E에서 ScenePhase 감지 + 오버레이 + 카메라 세션 정지
/// hook을 구현한다. 호출부(RootTabView의 .appBackgroundShield())는 그대로 유지.
struct AppBackgroundShieldModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
        // Plan E: ScenePhase + 오버레이 추가
    }
}

extension View {
    /// 앱이 백그라운드 진입 시 보호 가림막을 씌운다 (Plan E에서 활성화).
    func appBackgroundShield() -> some View {
        modifier(AppBackgroundShieldModifier())
    }
}
