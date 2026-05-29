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
    @State private var isExporting = false
    @State private var exportShareItem: ExportShareItem?
    @State private var exportError: String?
    @State private var isCloudSyncVisible = false
    @State private var cloudSyncEnabled = false
    @State private var cloudSyncStatus: CloudSyncStatus = .disabled
    @State private var cloudSyncError: String?

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

                Section {
                    Button {
                        Task { await exportAll() }
                    } label: {
                        if isExporting {
                            HStack {
                                ProgressView()
                                Text("settings_export_in_progress")
                            }
                        } else {
                            Label("settings_export_all", systemImage: "square.and.arrow.up")
                        }
                    }
                    .disabled(isExporting)
                } header: {
                    Text("settings_section_backup")
                } footer: {
                    Text("settings_export_local_only_note")
                }

                if isCloudSyncVisible {
                    Section {
                        Toggle(
                            "settings_icloud_sync_toggle",
                            isOn: Binding(
                                get: { cloudSyncEnabled },
                                set: { newValue in
                                    Task { await setCloudSyncEnabled(newValue) }
                                }
                            )
                        )

                        Button {
                            Task { await syncToICloud() }
                        } label: {
                            Label("settings_icloud_sync_now", systemImage: "arrow.triangle.2.circlepath.icloud")
                        }
                        .disabled(!cloudSyncEnabled || cloudSyncIsBusy)

                        Button {
                            Task { await restoreFromICloud() }
                        } label: {
                            Label("settings_icloud_restore", systemImage: "icloud.and.arrow.down")
                        }
                        .disabled(!cloudSyncEnabled || cloudSyncIsBusy)

                        Text(cloudSyncStatusDescription)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    } header: {
                        Text("settings_section_icloud")
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
            await refreshCloudSyncState()
        }
        .sheet(isPresented: $showTrash) {
            TrashScreen()
                .environmentObject(deps)
        }
        .sheet(item: $exportShareItem, onDismiss: {
            if let exportShareItem {
                Task { await deps.exportService.cleanupExport(at: exportShareItem.url) }
            }
            exportShareItem = nil
        }) { item in
            ShareSheetController(activityItems: [item.url]) {}
        }
        .alert(
            "settings_export_error_title",
            isPresented: exportErrorBinding,
            presenting: exportError
        ) { _ in
            Button("button_ok", role: .cancel) { exportError = nil }
        } message: { message in
            Text(message)
        }
        .alert(
            "settings_icloud_error_title",
            isPresented: cloudSyncErrorBinding,
            presenting: cloudSyncError
        ) { _ in
            Button("button_ok", role: .cancel) { cloudSyncError = nil }
        } message: { message in
            Text(message)
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

    @MainActor
    private func exportAll() async {
        isExporting = true
        defer { isExporting = false }
        do {
            let url = try await deps.exportService.prepareExport()
            exportShareItem = ExportShareItem(url: url)
        } catch {
            exportError = String(describing: error)
        }
    }

    @MainActor
    private func refreshCloudSyncState() async {
        isCloudSyncVisible = await deps.cloudSyncController.featureVisible()
        guard isCloudSyncVisible else { return }
        cloudSyncEnabled = await deps.cloudSyncController.isEnabled()
        guard cloudSyncEnabled else {
            cloudSyncStatus = .disabled
            return
        }
        cloudSyncStatus = .checkingAccount
        let accountState = await deps.cloudSyncController.accountState()
        cloudSyncStatus = .ready(accountState)
    }

    @MainActor
    private func setCloudSyncEnabled(_ enabled: Bool) async {
        do {
            try await deps.cloudSyncController.setEnabled(enabled)
            cloudSyncEnabled = enabled
            await refreshCloudSyncState()
        } catch {
            cloudSyncError = CloudSyncErrorPresentation.message(for: error)
        }
    }

    @MainActor
    private func syncToICloud() async {
        cloudSyncStatus = .syncing
        do {
            let summary = try await deps.cloudSyncController.syncNow()
            cloudSyncStatus = .synced(summary)
        } catch {
            let message = CloudSyncErrorPresentation.message(for: error)
            cloudSyncStatus = .failed(message)
            cloudSyncError = message
        }
    }

    @MainActor
    private func restoreFromICloud() async {
        cloudSyncStatus = .restoring
        do {
            let summary = try await deps.cloudSyncController.restoreFromCloud()
            cloudSyncStatus = .restored(summary)
        } catch {
            let message = CloudSyncErrorPresentation.message(for: error)
            cloudSyncStatus = .failed(message)
            cloudSyncError = message
        }
    }

    private var cloudSyncIsBusy: Bool {
        switch cloudSyncStatus {
        case .checkingAccount, .syncing, .restoring:
            return true
        case .disabled, .ready, .synced, .restored, .failed:
            return false
        }
    }

    private var cloudSyncStatusDescription: String {
        switch cloudSyncStatus {
        case .disabled:
            return String(localized: "settings_icloud_status_disabled")
        case .checkingAccount:
            return String(localized: "settings_icloud_status_checking")
        case .ready(let accountState):
            return accountState.statusDescription
        case .syncing:
            return String(localized: "settings_icloud_status_syncing")
        case .synced(let summary):
            return String(
                format: String(localized: "settings_icloud_status_synced_format"),
                summary.sessionCount,
                summary.photoCount
            )
        case .restoring:
            return String(localized: "settings_icloud_status_restoring")
        case .restored(let summary):
            return String(
                format: String(localized: "settings_icloud_status_restored_format"),
                summary.sessionCount,
                summary.photoCount,
                summary.assetCount
            )
        case .failed:
            return String(localized: "settings_icloud_status_failed")
        }
    }

    private var exportErrorBinding: Binding<Bool> {
        Binding(
            get: { exportError != nil },
            set: { newValue in
                if !newValue { exportError = nil }
            }
        )
    }

    private var cloudSyncErrorBinding: Binding<Bool> {
        Binding(
            get: { cloudSyncError != nil },
            set: { newValue in
                if !newValue { cloudSyncError = nil }
            }
        )
    }
}

private struct ExportShareItem: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}

private extension CloudSyncAccountState {
    var statusDescription: String {
        switch self {
        case .available:
            return String(localized: "settings_icloud_status_ready")
        case .noAccount:
            return String(localized: "settings_icloud_status_no_account")
        case .restricted:
            return String(localized: "settings_icloud_status_restricted")
        case .couldNotDetermine:
            return String(localized: "settings_icloud_status_unknown")
        case .temporarilyUnavailable:
            return String(localized: "settings_icloud_status_temporarily_unavailable")
        }
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
