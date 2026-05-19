import Foundation

/// `Bundle(for: CamorkBundleToken.self)`로 app bundle을 명시적으로 잡기 위한 토큰.
///
/// `Bundle.main`은 test 호스팅 환경에 따라 host app bundle이 아닐 수 있으며,
/// `Bundle(for: ...)`를 test target 클래스로 호출하면 test bundle이 잡혀
/// app target 자산(Asset Catalog) lookup이 실패한다. 이 클래스를 app target 안에
/// 두면 `Bundle(for: CamorkBundleToken.self)`가 항상 app bundle을 반환.
internal final class CamorkBundleToken {}
