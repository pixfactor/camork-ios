import SwiftUI

/// 통일 카드 컨테이너 — 갤러리 세션 카드, 설정 카드 등 카드 UI의 공통 기반.
///
/// 단위 테스트 없음 (정책: SwiftUI View 자체의 시각 검증은 Preview에 위임).
struct CamorkCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(Spacing.md)
            .background(Color.camorkSecondaryBackground)
            .clipShape(RoundedRectangle(cornerRadius: CornerRadius.lg, style: .continuous))
    }
}

#Preview("Dark") {
    ZStack {
        Color.camorkBackground.ignoresSafeArea()
        CamorkCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("카드 제목").font(.headline)
                Text("부제목입니다").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding()
    }
    .preferredColorScheme(.dark)
}

#Preview("Light") {
    ZStack {
        Color.camorkBackground.ignoresSafeArea()
        CamorkCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("카드 제목").font(.headline)
                Text("부제목입니다").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding()
    }
    .preferredColorScheme(.light)
}

#Preview("AX5") {
    ZStack {
        Color.camorkBackground.ignoresSafeArea()
        CamorkCard {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                Text("카드 제목").font(.headline)
                Text("부제목입니다").font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding()
    }
    .dynamicTypeSize(.accessibility5)
    .preferredColorScheme(.dark)
}
