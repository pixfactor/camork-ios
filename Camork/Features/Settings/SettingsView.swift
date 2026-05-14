import SwiftUI

struct SettingsView: View {
    @StateObject private var authManager = AuthenticationManager.shared
    @State private var storageUsed: Int64 = 0
    @State private var showClearCacheAlert = false
    @State private var showClearCacheSuccess = false

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }

    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }

    var body: some View {
        NavigationStack {
            Form {
                // MARK: 보안
                Section {
                    HStack {
                        Label("앱 잠금", systemImage: "lock.fill")
                        Spacer()
                        Toggle("", isOn: $authManager.isLockEnabled)
                            .labelsHidden()
                    }

                    if authManager.isLockEnabled {
                        HStack {
                            Label("인증 방식", systemImage: biometryIcon)
                            Spacer()
                            Text(authManager.biometryDisplayName)
                                .foregroundStyle(.secondary)
                                .font(.subheadline)
                        }
                    }
                } header: {
                    Text("보안")
                } footer: {
                    if authManager.isLockEnabled {
                        Text("앱을 백그라운드로 전환하면 자동으로 잠깁니다.")
                    }
                }

                // MARK: 공유
                Section {
                    HStack {
                        Label("표준 공유 지원", systemImage: "square.and.arrow.up")
                        Spacer()
                        Text("AirDrop, 파일, 메신저")
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }
                } header: {
                    Text("공유")
                } footer: {
                    Text("사진 상세 화면이나 폴더 선택 모드에서 사진 앱 저장, AirDrop, 파일 앱, 메신저 공유를 바로 사용할 수 있습니다.")
                }

                // MARK: 저장소
                Section {
                    HStack {
                        Label("사용 중인 저장 공간", systemImage: "internaldrive")
                        Spacer()
                        Text(ByteCountFormatter.string(fromByteCount: storageUsed, countStyle: .file))
                            .foregroundStyle(.secondary)
                            .font(.subheadline)
                    }

                    Button(role: .destructive) {
                        showClearCacheAlert = true
                    } label: {
                        Label("캐시 삭제", systemImage: "trash")
                    }
                } header: {
                    Text("저장소")
                } footer: {
                    Text("캐시를 삭제해도 미디어 파일은 삭제되지 않습니다.")
                }

                // MARK: 정보
                Section("정보") {
                    HStack {
                        Text("앱 버전")
                        Spacer()
                        Text(appVersion)
                            .foregroundStyle(.secondary)
                    }

                    HStack {
                        Text("빌드 번호")
                        Spacer()
                        Text(buildNumber)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("설정")
            .alert("캐시 삭제", isPresented: $showClearCacheAlert) {
                Button("삭제", role: .destructive) {
                    clearCache()
                }
                Button("취소", role: .cancel) {}
            } message: {
                Text("임시 파일과 캐시를 삭제합니다. 미디어 파일은 영향받지 않습니다.")
            }
            .alert("완료", isPresented: $showClearCacheSuccess) {
                Button("확인") {}
            } message: {
                Text("캐시가 삭제되었습니다.")
            }
            .task {
                storageUsed = await FileStorageManager.shared.calculateStorageUsed()
            }
        }
    }

    private var biometryIcon: String {
        switch authManager.checkBiometryType() {
        case .faceID: return "faceid"
        case .touchID: return "touchid"
        default: return "person.fill"
        }
    }

    private func clearCache() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        if let cachesURL = caches {
            let contents = (try? FileManager.default.contentsOfDirectory(
                at: cachesURL,
                includingPropertiesForKeys: nil
            )) ?? []
            for url in contents {
                try? FileManager.default.removeItem(at: url)
            }
        }
        Task {
            storageUsed = await FileStorageManager.shared.calculateStorageUsed()
        }
        showClearCacheSuccess = true
    }
}
