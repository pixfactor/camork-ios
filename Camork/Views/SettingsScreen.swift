import SwiftUI

/// Settings 화면 (Plan E Batch E4). 본 화면은 모든 항목이 read/persist 만 — 카메라/저장소
/// 같은 무거운 상태는 건드리지 않는다.
///
/// 구성:
/// - **앱 잠금** (Plan E E3.a + E3.b 의존): policy picker. E3.b 가 LAContext 인증을
///   붙이기 전까지는 picker만 노출되고 실제 잠금 화면은 E3.b 진입 후 활성화.
/// - **휴지통**: `TrashScreen` 모달 진입. E1.c 와 동일한 view를 재사용.
/// - **앱 정보**: 버전 / Bundle ID. App Store 정식 출시 카피는 별도 폴리시 단계.
struct SettingsScreen: View {
    @EnvironmentObject private var deps: DependencyContainer

    /// AppLockController는 actor — picker 바인딩은 async hop을 거치므로 @State로 미러링.
    @State private var lockPolicy: AppLockPolicy = .immediate
    @State private var showTrash = false

    var body: some View {
        NavigationStack {
            Form {
                Section("settings_section_app_lock") {
                    Picker("settings_lock_policy_label", selection: $lockPolicy) {
                        ForEach(AppLockPolicy.allCases, id: \.self) { policy in
                            Text(LocalizedStringKey(policy.localizationKey))
                                .tag(policy)
                        }
                    }
                    .onChange(of: lockPolicy) { _, newValue in
                        Task { await deps.appLockController.setPolicy(newValue) }
                    }
                }

                Section("settings_section_trash") {
                    Button {
                        showTrash = true
                    } label: {
                        Label("settings_open_trash", systemImage: "trash")
                    }
                }

                Section("settings_section_about") {
                    LabeledContent(
                        "settings_about_version",
                        value: Self.appVersion
                    )
                    LabeledContent(
                        "settings_about_bundle_id",
                        value: Self.bundleId
                    )
                }
            }
            .navigationTitle("settings_tab_label")
            .navigationBarTitleDisplayMode(.inline)
        }
        .task {
            lockPolicy = await deps.appLockController.policy
        }
        .sheet(isPresented: $showTrash) {
            TrashScreen()
                .environmentObject(deps)
        }
    }

    private static var appVersion: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }

    private static var bundleId: String {
        Bundle.main.bundleIdentifier ?? "—"
    }
}

private extension AppLockPolicy {
    /// SettingsScreen picker가 표시할 Localizable 키.
    var localizationKey: String {
        switch self {
        case .off: return "settings_lock_policy_off"
        case .immediate: return "settings_lock_policy_immediate"
        case .oneMinute: return "settings_lock_policy_one_minute"
        case .fiveMinutes: return "settings_lock_policy_five_minutes"
        case .fifteenMinutes: return "settings_lock_policy_fifteen_minutes"
        }
    }
}
