import SwiftUI

/// Bootstrap 실패 시 노출되는 retry-able 에러 화면 (ADR #9 `try!` 금지 → safe 분기).
///
/// `CamorkApp`에서 `Bootstrap.failed(error)` 분기로 진입. retry 콜백은 다시
/// `DependencyContainer()`를 시도 — 디스크 부족 / 권한 일시적 거부 등 transient
/// 에러에서 회복 가능.
struct StorageInitErrorView: View {
    let error: Error
    let retry: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)

            Text("storage_init_error_title")
                .font(.title2.weight(.semibold))
                .multilineTextAlignment(.center)

            Text("storage_init_error_description")
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Text(String(describing: error))
                .font(.caption.monospaced())
                .multilineTextAlignment(.center)
                .foregroundStyle(.tertiary)
                .lineLimit(3)
                .padding(.horizontal, 24)

            Button(action: retry) {
                Text("storage_init_error_retry")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .appBackgroundShield()
    }
}

#Preview("Dark") {
    StorageInitErrorView(
        error: CameraSessionError.noDevice,
        retry: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Light") {
    StorageInitErrorView(
        error: CameraSessionError.noDevice,
        retry: {}
    )
    .preferredColorScheme(.light)
}
