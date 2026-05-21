import SwiftUI

enum ChromeFadeMask {
    static let topHeight: CGFloat = 88
    static let topActivationOffset: CGFloat = 72
    static let topRampDistance: CGFloat = 80
    static let height: CGFloat = 280
    static let scrollReserve: CGFloat = 176

    static func topHeight(forScrolledDistance scrolledDistance: CGFloat) -> CGFloat {
        let scrolledDistance = max(scrolledDistance - topActivationOffset, 0)
        let progress = min(scrolledDistance / topRampDistance, 1)
        return topHeight * progress
    }
}

private struct ChromeFadeMaskModifier: ViewModifier {
    let bottomHeight: CGFloat

    func body(content: Content) -> some View {
        content
            .mask(alignment: .bottom) {
                VStack(spacing: 0) {
                    Color.black
                    LinearGradient(
                        stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black.opacity(0.98), location: 0.18),
                            .init(color: .black.opacity(0.78), location: 0.46),
                            .init(color: .black.opacity(0.34), location: 0.76),
                            .init(color: .black.opacity(0), location: 1)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: bottomHeight)
                }
                .ignoresSafeArea(edges: .bottom)
            }
    }
}

private struct TopChromeFadeOverlayModifier: ViewModifier {
    let height: CGFloat

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .top) {
                LinearGradient(
                    stops: [
                        .init(color: Color.camorkBackground, location: 0),
                        .init(color: Color.camorkBackground.opacity(0.82), location: 0.34),
                        .init(color: Color.camorkBackground.opacity(0), location: 1)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: height)
                .opacity(height > 1 ? 1 : 0)
                .allowsHitTesting(false)
            }
    }
}

extension View {
    func camorkChromeFadeMask(bottomHeight: CGFloat = ChromeFadeMask.height) -> some View {
        modifier(ChromeFadeMaskModifier(bottomHeight: bottomHeight))
    }

    func camorkTopChromeFadeOverlay(height: CGFloat) -> some View {
        modifier(TopChromeFadeOverlayModifier(height: height))
    }
}

struct ChromeFadeTopPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = 0

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct ChromeFadeTopProbe: View {
    let coordinateSpaceName: String

    var body: some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: ChromeFadeTopPreferenceKey.self,
                value: proxy.frame(in: .named(coordinateSpaceName)).minY
            )
        }
        .frame(height: 0)
    }
}
