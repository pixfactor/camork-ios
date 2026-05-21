import SwiftUI
import UIKit

/// 풀스크린 사진 디테일. 단일 또는 여러 사진을 좌우 스와이프로 전환. 아래 드래그로 dismiss.
///
/// 책임:
/// - `photos` 배열을 받아 `initialPhotoId`에서 시작하는 페이저 표시 (TabView .page style).
/// - 인접 사진 data는 `dataLoader` closure로 lazy load 후 `imageDataCache`에 보관.
///   현재 인덱스 변경 시 인접(±1) 사진을 prefetch.
/// - `ZoomableImageView`로 각 페이지에 pinch zoom + double-tap zoom + pan 지원.
/// - 메모 편집은 sheet에서 `PhotoMemoEditor.update` 호출. 저장 후 `savedNotes` 갱신.
/// - 아래 vertical drag로 dismiss. zoom > 1.0이면 UIScrollView가 pan을 가로채 자연스럽게
///   비활성. horizontal drag는 TabView swipe에 양보 (vertical-dominant downward만 reaction).
/// - 단일 사진 share entry: `session` + `sharePreparer`가 주입되면 상단 toolbar에
///   `ShareEntryButton(photos: [currentPhoto])`를 노출. CameraScreen latest 진입 경로에서는
///   nil로 두어 share affordance를 숨긴다.
struct PhotoDetailView: View {
    let photos: [Photo]
    let initialPhotoId: UUID
    let initialData: Data
    let dataLoader: (Photo) async throws -> Data
    let memoEditor: PhotoMemoEditor
    let onDismiss: () -> Void
    let session: Session?
    let sharePreparer: SharePreparer?

    @State private var currentIndex: Int
    @State private var imageDataCache: [UUID: Data]
    @State private var decodedImageCache: [UUID: UIImage]
    /// 메모 sheet의 TextEditor 편집 버퍼.
    @State private var note: String
    /// 실제로 저장된 메모 상태. metaBar 표시에 사용. photo (let) parameter의 stale 값을 덮어쓰기.
    @State private var savedNotes: [UUID: String?]
    @State private var showMemoSheet: Bool = false
    @State private var memoError: String?
    @State private var dismissOffset: CGFloat = 0

    init(
        photos: [Photo],
        initialPhotoId: UUID,
        initialData: Data,
        dataLoader: @escaping (Photo) async throws -> Data,
        memoEditor: PhotoMemoEditor,
        onDismiss: @escaping () -> Void,
        session: Session? = nil,
        sharePreparer: SharePreparer? = nil
    ) {
        self.photos = photos
        self.initialPhotoId = initialPhotoId
        self.initialData = initialData
        self.dataLoader = dataLoader
        self.memoEditor = memoEditor
        self.onDismiss = onDismiss
        self.session = session
        self.sharePreparer = sharePreparer

        let initialIndex = photos.firstIndex(where: { $0.id == initialPhotoId }) ?? 0
        self._currentIndex = State(initialValue: initialIndex)
        self._imageDataCache = State(initialValue: [initialPhotoId: initialData])
        var initialDecoded: [UUID: UIImage] = [:]
        if let img = UIImage(data: initialData) {
            initialDecoded[initialPhotoId] = img
        }
        self._decodedImageCache = State(initialValue: initialDecoded)

        let startingNote = photos.indices.contains(initialIndex) ? photos[initialIndex].note : nil
        self._note = State(initialValue: startingNote ?? "")
        var noteDict: [UUID: String?] = [:]
        for p in photos {
            noteDict[p.id] = p.note
        }
        self._savedNotes = State(initialValue: noteDict)
    }

    private var currentPhoto: Photo {
        photos[currentIndex]
    }

    private var currentSavedNote: String? {
        // [UUID: String?] 의 lookup은 String?? — outer nil(키 없음)/inner nil(메모 없음) 평탄화.
        savedNotes[currentPhoto.id] ?? nil
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 0) {
                topBar
                pager
                metaBar
            }
            .offset(y: dismissOffset)
        }
        .preferredColorScheme(.dark)
        .simultaneousGesture(dismissDragGesture)
        .task {
            await prefetchAdjacent(from: currentIndex)
        }
        .onChange(of: currentIndex) { _, newIndex in
            let photo = photos[newIndex]
            note = (savedNotes[photo.id] ?? nil) ?? ""
            Task { await prefetchAdjacent(from: newIndex) }
        }
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
            Button("button_close", action: onDismiss)
                .font(.title3.weight(.semibold))
                .padding(12)
                .accessibilityLabel(Text("photo_detail_close_a11y"))

            Spacer()

            if let session, let sharePreparer {
                ShareEntryButton(
                    session: session,
                    photos: [currentPhoto],
                    sharePreparer: sharePreparer
                )
                .font(.title3.weight(.semibold))
                .padding(12)
                .id(currentPhoto.id)
            }

            Button {
                note = currentSavedNote ?? ""
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

    private var pager: some View {
        TabView(selection: $currentIndex) {
            ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                photoPage(photo: photo)
                    .tag(index)
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func photoPage(photo: Photo) -> some View {
        if let image = decodedImageCache[photo.id] {
            ZoomableImageView(image: image)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if imageDataCache[photo.id] != nil {
            VStack(spacing: 12) {
                Image(systemName: "photo")
                    .font(.largeTitle)
                Text("photo_detail_image_unavailable")
                    .font(.body)
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .task { await ensureData(for: photo) }
        }
    }

    private var metaBar: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(currentPhoto.capturedAt.formatted(date: .numeric, time: .shortened))
                .font(.caption)
                .foregroundStyle(.white)
            if let placeName = currentPhoto.location?.placeName, !placeName.isEmpty {
                Text(placeName)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
            if let saved = currentSavedNote, !saved.isEmpty {
                Text(saved)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                            note = currentSavedNote ?? ""
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

    // MARK: - Drag dismiss

    /// vertical-dominant downward drag만 따라가며 dismissOffset 갱신. horizontal은 TabView swipe에
    /// 양보. zoom > 1.0인 페이지에서는 ZoomableImageView의 UIScrollView pan이 우선이라 본 gesture가
    /// 거의 트리거되지 않음.
    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 20)
            .onChanged { value in
                guard value.translation.height > 0,
                      abs(value.translation.height) > abs(value.translation.width) else {
                    return
                }
                dismissOffset = value.translation.height
            }
            .onEnded { value in
                let isVerticalDown = value.translation.height > 0 &&
                    abs(value.translation.height) > abs(value.translation.width)
                if isVerticalDown && value.translation.height > 120 {
                    onDismiss()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        dismissOffset = 0
                    }
                }
            }
    }

    // MARK: - Memo save

    @MainActor
    private func saveMemo() async {
        let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedNote: String? = trimmed.isEmpty ? nil : trimmed
        let photoId = currentPhoto.id
        do {
            try await memoEditor.update(photoId: photoId, note: resolvedNote)
            savedNotes[photoId] = resolvedNote
            showMemoSheet = false
        } catch {
            memoError = String(describing: error)
        }
    }

    // MARK: - Data load

    @MainActor
    private func ensureData(for photo: Photo) async {
        if decodedImageCache[photo.id] != nil { return }
        do {
            let data = try await dataLoader(photo)
            imageDataCache[photo.id] = data
            decodedImageCache[photo.id] = UIImage(data: data)
        } catch {
            // 무시 — placeholder가 표시됨
        }
    }

    private func prefetchAdjacent(from index: Int) async {
        let candidates = [index, index - 1, index + 1]
        for i in candidates where i >= 0 && i < photos.count {
            await ensureData(for: photos[i])
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
        scrollView.bounces = false
        scrollView.isDirectionalLockEnabled = true
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.decelerationRate = .fast
        scrollView.showsHorizontalScrollIndicator = false
        scrollView.showsVerticalScrollIndicator = false
        scrollView.backgroundColor = .clear
        scrollView.panGestureRecognizer.isEnabled = false

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
            context.coordinator.updatePanAvailability(in: scrollView)
        }
    }

    final class Coordinator: NSObject, UIScrollViewDelegate {
        weak var imageView: UIImageView?

        func viewForZooming(in scrollView: UIScrollView) -> UIView? {
            imageView
        }

        func scrollViewDidZoom(_ scrollView: UIScrollView) {
            updatePanAvailability(in: scrollView)
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

        func updatePanAvailability(in scrollView: UIScrollView) {
            scrollView.panGestureRecognizer.isEnabled =
                scrollView.zoomScale > scrollView.minimumZoomScale + 0.01
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
