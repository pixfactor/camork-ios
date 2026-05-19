import Testing
import SwiftUI
import UIKit
@testable import Camork

@Suite("Semantic colors")
struct ColorsTests {
    @Test("AccentColor는 라이트/다크에서 다른 RGBA를 가진다")
    func accentDiffersBetweenAppearances() {
        // Bundle.main은 test 호스팅 환경에 따라 host app이 아닐 수 있어 nil 반환 발생.
        // app target에 CamorkBundleToken 클래스를 두고 Bundle(for:)로 명시적으로 잡으면
        // 항상 app bundle을 반환 → Asset Catalog의 AccentColor lookup 성공.
        let appBundle = Bundle(for: CamorkBundleToken.self)
        guard let asset = UIColor(named: "AccentColor", in: appBundle, compatibleWith: nil) else {
            Issue.record("AccentColor가 app 번들에 등록돼 있어야 함")
            return
        }

        // UIColor object 비교(==)는 내부 representation에 의존해 약함 → 명시적 RGBA 컴포넌트 비교.
        let light = asset.resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
        let dark = asset.resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))

        var lr: CGFloat = 0, lg: CGFloat = 0, lb: CGFloat = 0, la: CGFloat = 0
        var dr: CGFloat = 0, dg: CGFloat = 0, db: CGFloat = 0, da: CGFloat = 0
        light.getRed(&lr, green: &lg, blue: &lb, alpha: &la)
        dark.getRed(&dr, green: &dg, blue: &db, alpha: &da)

        let sameRGB = (lr == dr) && (lg == dg) && (lb == db)
        #expect(!sameRGB, "라이트/다크 RGB가 동일하면 다크 변형 자체가 무의미")
    }

    @Test("Camork 시멘틱 컬러는 인스턴스화 가능")
    func semanticColorsInstantiate() {
        _ = Color.camorkAccent
        _ = Color.camorkBackground
        _ = Color.camorkSecondaryBackground
        _ = Color.camorkTertiaryBackground
        _ = Color.camorkSeparator
        _ = Color.camorkFill
    }
}
