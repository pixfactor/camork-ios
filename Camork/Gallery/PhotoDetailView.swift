import SwiftUI
import UIKit

/// 풀스크린 사진 디테일. CameraScreen의 latest thumbnail / SessionDetailScreen의 grid 탭 진입점.
///
/// 책임:
/// - 받은 `Data`를 `UIImage(data:)`로 디코드 시도. 실패하면
///   `photo_detail_image_unavailable` 안내로 fallback (테스트 환경의 4-byte fake JPEG에
///   안전).
/// - 디코드 성공 시 `ZoomableImageView` (UIScrollView 기반)로 pinch zoom + double-tap
///   zoom + pan 지원 (spec 7.2 / 10.4 / Plan B Phase 3.2 Step 2).
/// - 메모 편집은 sheet에서 `PhotoMemoEditor.update` 호출. notFound / IO 에러는 alert로
///   표시 후 화면 유지 (사용자 입력 유실 방지).
/// - metaBar의 note indicator는 init parameter `photo.note`가 아닌 로컬 `savedNote`
///   @State를 사용 — 사용자가 sheet에서 저장한 즉시 반영 (dismiss/reopen 기다리지 않음).
/// - 단일 사진 share entry (Plan D Batch D2): `session` + `sharePreparer`가 주입되면
///   상단 toolbar에 `ShareEntryButton(photos: [photo])`를 노출. SessionDetailScreen 진입
///   경로에서는 두 값 모두 전달, CameraScreen latest 진입 경로에서는 nil로 두어 share
///   affordance를 숨긴다 (session context가 없는 진입은 v1.x에서 출시 보류).
struct PhotoDetailView: View {
    let photo: Photo
    let data: Data
    let memoEditor: PhotoMemoEditor
    let onDismiss: () -> Void
    let session: Session?
    let sharePreparer: SharePreparer?

    /// 메모 sheet의 TextEditor 편집 버퍼.
    @State private var note: String
    /// 실제로 저장된 메모 상태. metaBar의 note.text 아이콘 표시에 사용. 저장 성공 시
    /// 즉시 갱신되어 photo (let) parameter의 stale 값을 덮어쓰기.
    @State private var savedNote: String?
    @State private var showMemoSheet: Bool = false
    @State private var memoError: String?
    /// data를 init에서 한 번 디코드. body 재평가마다 UIImage(data:)를 재호출하지 않음.
    @State private var decodedImage: UIImage?

    init(
        photo: Photo,
        data: Data,
        memoEditor: PhotoMemoEditor,
        onDismiss: @escaping () -> Void,
        session: Session? = nil,
        sharePreparer: SharePreparer? = nil
    ) {
        self.photo = photo
        self.data = data
        self.memoEditor = memoEditor
        self.onDismiss = onDismiss
        self.session = session
        self.sharePreparer = sharePreparer
        let initialNote = photo.note
        self._note = State(initialValue: initialNote ?? "")
        self._savedNote = State(initialValue: initialNote)
        self._decodedImage = State(initialValue: UIImage(data: data))
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                imageView
                metaBar
            }
        }
        .preferredColorScheme(.dark)
        .sheet(isPresented: $showMemoSheet) {
            memoSheet
        }
        .alert(
            "memo_save_error_title",
            isPresented: memoErrorBinding,
            presenting: memoError
        ) { _ in
            Button("button_ok", role: .cancel) { memoError = nil }
        } message: { message in
            Text(message)
        }
    }

    // MARK: - Subviews

    private var topBar: some View {
        HStack(spacing: 0) {
            Button(action: onDismiss) {
                Image(systemName: "chevron.down")
                    .font(.title3.weight(.semibold))
                    .padding(12)
            }
            .accessibilityLabel(Text("photo_detail_close_a11y"))

            Spacer()

            if let session, let sharePreparer {
                ShareEntryButton(
                    session: session,
                    photos: [photo],
                    sharePreparer: sharePreparer
                )
                .font(.title3.weight(.semibold))
                .padding(12)
            }

            Button {
                note = savedNote ?? ""
                showMemoSheet = true
            } label: {
                Image(systemName: "square.and.pencil")
                    .font(.title3.weight(.semibold))
                    .padding(12)
            }
            .accessibilityLabel(Text("photo_detail_edit_memo_a11y"))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
    }

    @ViewBuilder
    private var imageView: some View {
        if let image = decodedImage {
            ZoomableImageView(image: image)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: 12) {
                Image(systemName: "photo")
                    .font(.largeTitle)
                Text("photo_detail_image_unavailable")
                    .font(.body)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var metaBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(photo.capturedAt.formatted(date: .numeric, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.white)
                if let placeName = photo.location?.placeName, !placeName.isEmpty {
                    Text(placeName)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            Spacer()
            if let saved = savedNote, !saved.isEmpty {
                Image(systemName: "note.text")
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
        .padding(16)
        .background(Color.black.opacity(0.5))
    }

    private var memoSheet: some View {
        NavigationStack {
            TextEditor(text: $note)
                .padding(16)
                .navigationTitle(Text("photo_detail_memo_title"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("button_cancel") {
                            note = savedNote ?? ""
                            showMemoSheet = false
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("button_save") {
                            Task { await saveMemo() }
                        }
                    }
                }
        }
    }

    // MARK: - Memo save

    @MainActor
    private func saveMemo() async {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedNote: String? = trimmed.isEmpty ? nil : trimmed
        do {
            try await memoEditor.update(photoId: photo.id, note: resolvedNote)
            savedNote = resolvedNote
            showMemoSheet = false
        } catch {
            memoError = String(describing: error)
        }
    }

    // MARK: - Alert binding

    private var memoErrorBinding: Binding<Bool> {
        Binding(
            get: { memoError != nil },
            set: { newValue in
                if !newValue { memoError = nil }
            }
        )
    }
}

// MARK: - Zoomable image view (UIScrollView-backed)

/// UIScrollView + UIImageView 조합으로 pinch zoom (1.0 ~ 4.0), 더블탭 zoom toggle,
/// pan을 지원. Plan B Phase 3.2 Step 2 / spec 7.2 / 10.4 요구사항 충족.
///
/// UIViewRepresentable이라 SwiftUI body 재평가 시 동일 UIScrollView 인스턴스가
/// 재사용되어 zoom level / pan offset이 유지됨.
struct ZoomableImageView: UIViewRepresentable {
    let image: UIImage

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIScrollView {
        let scrollView = UIScrollView()
        scrollView.delegate = context.coordinator
        scrollView.minimumZoomScale = 1.0
        scrollView.maximumZoomScale = 4.0
        scrollView.bouncesZoom = true
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear

        let imageView = UIImageView(image: image)
        imageView.contentMode = .scaleAspectFit
        imageView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(imageView)
        context.coordinator.imageView = imageView

        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor),
            imageView.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            imageView.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor),
            imageView.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        let doubleTap = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleDoubleTap(_:))
        )
        doubleTap.numberOfTapsRequired = 2
        scrollView.addGestureRecognizer(doubleTap)

        return scrollView
    }

    func updateUIView(_ scrollView: UIScrollView, context: Context) {
        // image는 let property이고 PhotoDetailView가 decoded UIImage를 @State로 1회
        // 캐시하므로 동일 인스턴스가 흐름. 인스턴스가 바뀐 경우에만 갱신해 zoom 상태 보존.
        if context.coordinator.imageView?.image !== image {
            context.coordinator.imageView?.image = image
            scrollView.setZoomScale(scrollView.minimumZoomScale, animated: false)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let scrollView = gesture.view as? UIScrollView else { return }
            if scrollView.zoomScale > scrollView.minimumZoomScale {
                scrollView.setZoomScale(scrollView.minimumZoomScale, animated: true)
            } else {
                let location = gesture.location(in: imageView)
                let zoomRect = Self.makeZoomRect(scrollView: scrollView, scale: 2.0, center: location)
                scrollView.zoom(to: zoomRect, animated: true)
            }
        }

        private static func makeZoomRect(scrollView: UIScrollView, scale: CGFloat, center: CGPoint) -> CGRect {
            let size = scrollView.bounds.size
            let width = size.width / scale
            let height = size.height / scale
            let originX = center.x - width / 2
            let originY = center.y - height / 2
            return CGRect(x: originX, y: originY, width: width, height: height)
        }
    }
}
