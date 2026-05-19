import SwiftUI

/// 통일 액션 버튼 — HIG §10 "한 화면 borderedProminent 1개 원칙"을 준수.
struct CamorkButton: View {
    enum Role {
        case primary       // 강조 액션 (저장, 공유 등)
        case secondary     // 보조 액션 (취소 등)
        case destructive   // 파괴 액션 (삭제)
    }

    /// SwiftUI `Color`의 동등 비교가 representation에 의존해 불안정 → 토큰으로 추상화.
    /// View 단에서 `color(for:)`로 실제 Color에 매핑.
    enum TintToken: Equatable {
        case accent          // 강조 — Color.camorkAccent
        case systemDefault   // 시스템 기본 (.bordered가 자동 처리)
        case destructive     // 파괴 — Color.red
    }

    struct ResolvedStyle: Equatable {
        let isProminent: Bool
        let tint: TintToken
    }

    let title: LocalizedStringKey
    let role: Role
    let action: () -> Void

    var body: some View {
        let style = Self.resolveStyle(role)
        return Group {
            if style.isProminent {
                Button(action: action) { label }
                    .buttonStyle(.borderedProminent)
                    .tint(color(for: style.tint))
            } else {
                Button(action: action) { label }
                    .buttonStyle(.bordered)
            }
        }
        .controlSize(.large)
    }

    private var label: some View {
        Text(title)
            .frame(maxWidth: .infinity, minHeight: 44)
    }

    private func color(for token: TintToken) -> Color? {
        switch token {
        case .accent: .camorkAccent
        case .systemDefault: nil    // borderedProminent 분기에서는 호출되지 않음
        case .destructive: .red
        }
    }

    /// 단위 테스트용 — role 분기 로직만 추출.
    static func resolveStyle(_ role: Role) -> ResolvedStyle {
        switch role {
        case .primary:
            ResolvedStyle(isProminent: true, tint: .accent)
        case .secondary:
            ResolvedStyle(isProminent: false, tint: .systemDefault)
        case .destructive:
            ResolvedStyle(isProminent: true, tint: .destructive)
        }
    }
}

#Preview("Dark") {
    VStack(spacing: Spacing.md) {
        CamorkButton(title: "button_share", role: .primary) {}
        CamorkButton(title: "button_cancel", role: .secondary) {}
        CamorkButton(title: "button_delete", role: .destructive) {}
    }
    .padding()
    .background(Color.camorkBackground)
    .preferredColorScheme(.dark)
}

#Preview("Light") {
    VStack(spacing: Spacing.md) {
        CamorkButton(title: "button_share", role: .primary) {}
        CamorkButton(title: "button_cancel", role: .secondary) {}
        CamorkButton(title: "button_delete", role: .destructive) {}
    }
    .padding()
    .background(Color.camorkBackground)
    .preferredColorScheme(.light)
}

#Preview("AX5") {
    VStack(spacing: Spacing.md) {
        CamorkButton(title: "button_share", role: .primary) {}
        CamorkButton(title: "button_cancel", role: .secondary) {}
        CamorkButton(title: "button_delete", role: .destructive) {}
    }
    .padding()
    .background(Color.camorkBackground)
    .dynamicTypeSize(.accessibility5)
    .preferredColorScheme(.dark)
}
