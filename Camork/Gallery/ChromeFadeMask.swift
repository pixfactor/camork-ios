import SwiftUI

/// Scroll edge effects for gallery surfaces. Replaces the older mask-based fade
/// implementation that alpha-clipped the scroll content itself.
///
/// - **iOS 26+**: native `.scrollEdgeEffectStyle(.soft, for: [.top, .bottom])` —
///   Liquid Glass-aware soft edge that blurs content sliding under safe area
///   chrome without trimming it.
/// - **iOS 17~25**: top/bottom `.ultraThinMaterial` overlays. The overlay's own
///   alpha is gradient-masked, **not the underlying content**, so cards keep
///   their full pixel data behind the chrome rather than visually disappearing.
enum ChromeFadeMask {
    /// ScrollView 콘텐츠 끝에 두는 bottom reserve. 마지막 카드가 chrome material
    /// overlay 뒤로 완전히 가려지지 않도록 두는 안전망 — tab bar(~49pt) +
    /// safe area bottom(~34pt) 합산 영역보다 약간 큰 여유 padding.
    static let scrollReserve: CGFloat = 96
}

private struct ScrollEdgeEffectsModifier: ViewModifier {
    let topEdgeHeight: CGFloat
    let bottomEdgeHeight: CGFloat

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            content
                .scrollEdgeEffectStyle(.soft, for: [.top, .bottom])
        } else {
            content
                .overlay(alignment: .top) {
                    EdgeMaterialBar(edge: .top, height: topEdgeHeight)
                }
                .overlay(alignment: .bottom) {
                    EdgeMaterialBar(edge: .bottom, height: bottomEdgeHeight)
                }
        }
    }
}

/// Gradient-masked thin material strip used as the iOS 17~25 fallback.
///
/// `.mask` is applied to the Rectangle (the overlay) — not to the scroll
/// content. The material's alpha fades from solid at the screen edge to
/// transparent where it meets the regular content area, so the chrome
/// transition feels soft without cropping any card pixels behind it.
private struct EdgeMaterialBar: View {
    enum Edge { case top, bottom }

    let edge: Edge
    let height: CGFloat

    var body: some View {
        Rectangle()
            .fill(.ultraThinMaterial)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.45),
                        .init(color: .black.opacity(0), location: 1)
                    ],
                    startPoint: edge == .top ? .top : .bottom,
                    endPoint: edge == .top ? .bottom : .top
                )
            }
            .frame(height: height)
            .allowsHitTesting(false)
            .ignoresSafeArea(.container, edges: edge == .top ? .top : .bottom)
    }
}

extension View {
    /// 스크롤 표면에 chrome edge effect를 입힌다. iOS 26+에서는
    /// `.scrollEdgeEffectStyle(.soft, for: [.top, .bottom])`, iOS 17~25에서는
    /// 상하단 `.ultraThinMaterial` 오버레이로 fallback. 본 modifier는 콘텐츠
    /// 자체에 alpha mask를 적용하지 않으므로 카드/사진 그리드가 chrome 뒤로
    /// 자연스럽게 흐르되 잘리지 않는다.
    func camorkScrollEdgeEffects(
        topEdgeHeight: CGFloat = 88,
        bottomEdgeHeight: CGFloat = 120
    ) -> some View {
        modifier(ScrollEdgeEffectsModifier(
            topEdgeHeight: topEdgeHeight,
            bottomEdgeHeight: bottomEdgeHeight
        ))
    }
}
