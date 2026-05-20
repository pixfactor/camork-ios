import SwiftUI

struct ShareEntryButton: View {
    let session: Session
    let photos: [Photo]
    let sharePreparer: SharePreparer

    @State private var includeLocation = true
    @State private var includeTime = true
    @State private var presentation: SharePresentation?
    @State private var isPreparing = false
    @State private var showPrepareError = false
    /// 사용자가 composer에서 편집하는 share 본문 텍스트. 옵션 sheet 진입 시
    /// `sharePreparer.autoText(...)`로 초기화되어 사용자가 수정 가능. 빈 문자열
    /// 도 의도된 선택으로 SharePreparer로 그대로 전달된다 (Plan D D1).
    @State private var customText: String = ""

    var body: some View {
        Button {
            openOptions()
        } label: {
            Image(systemName: "square.and.arrow.up")
        }
        .disabled(photos.isEmpty || isPreparing)
        .accessibilityLabel(Text("session_detail_share_a11y"))
        .sheet(item: $presentation) { presentation in
            switch presentation {
            case .options:
                optionsSheet
            case .share(let bundle):
                ShareSheetController(
                    activityItems: activityItems(for: bundle),
                    onCompletion: {
                        Task { await finishShare(bundle) }
                    }
                )
            }
        }
        .alert("share_prepare_error_title", isPresented: $showPrepareError) {
            Button("button_ok", role: .cancel) {}
        } message: {
            Text("share_prepare_error_message")
        }
    }

    private var optionsSheet: some View {
        NavigationStack {
            Form {
                Section("share_options_text_label") {
                    TextEditor(text: $customText)
                        .frame(minHeight: 88)
                        .accessibilityLabel(Text("share_options_text_label"))
                }

                Section {
                    Toggle("share_include_location", isOn: $includeLocation)
                        .disabled(!hasLocation)
                    Toggle("share_include_time", isOn: $includeTime)
                }

                Section {
                    Button {
                        Task { await prepareShare() }
                    } label: {
                        HStack {
                            Spacer()
                            if isPreparing {
                                ProgressView()
                            } else {
                                Text("button_share")
                            }
                            Spacer()
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isPreparing)
                }
            }
            .navigationTitle(Text("share_options_title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("button_cancel") {
                        presentation = nil
                    }
                }
            }
        }
    }

    private var hasLocation: Bool {
        session.firstLocation != nil || photos.contains { $0.location != nil }
    }

    private func openOptions() {
        includeLocation = hasLocation
        includeTime = true
        // composer 진입 시 토글 기본값(includeLocation=hasLocation, includeTime=true)을
        // 기준으로 자동 텍스트 합성. sharePreparer.autoText는 nonisolated라
        // 동기 호출 안전 (Plan D Batch D1).
        customText = sharePreparer.autoText(
            session: session,
            photos: photos,
            includeLocation: includeLocation,
            includeTime: includeTime
        )
        presentation = .options
    }

    @MainActor
    private func prepareShare() async {
        guard !isPreparing else { return }
        isPreparing = true
        defer { isPreparing = false }

        do {
            let bundle = try await sharePreparer.prepare(
                photos: photos,
                session: session,
                includeLocation: includeLocation,
                includeTime: includeTime,
                overrideText: customText
            )
            // If the options sheet was dismissed during prepare (Cancel tap or
            // swipe-down), do not resurrect the flow with a share sheet the user
            // never asked for — clean up the prepared bundle instead.
            guard case .options = presentation else {
                await sharePreparer.cleanup(bundle)
                return
            }
            presentation = .share(bundle)
        } catch {
            // Same guard: only surface a prepare error while the originating
            // options sheet is still on screen.
            if case .options = presentation {
                showPrepareError = true
            }
        }
    }

    @MainActor
    private func finishShare(_ bundle: ShareBundle) async {
        await sharePreparer.cleanup(bundle)
        presentation = nil
    }

    private func activityItems(for bundle: ShareBundle) -> [Any] {
        bundle.fileURLs.map { $0 as Any } + [bundle.autoText]
    }
}

private enum SharePresentation: Identifiable {
    case options
    case share(ShareBundle)

    var id: String {
        switch self {
        case .options:
            return "options"
        case .share(let bundle):
            return bundle.tempDir.path
        }
    }
}
