import Foundation
import SwiftUI
import UIKit

/// Async thumbnail image surface (Plan C Phase 3.3).
///
/// Loading is intentionally view-local: MediaStorage owns cache/read/generate behavior,
/// while this view owns only lifecycle cancellation and placeholder fallback.
///
/// **Invariant — loaded data *and* in-flight task are keyed by photo.id.**
/// `@State loadedThumbnail`은 `(photoID, data)` 쌍을 함께 보관하고, body는
/// `loadedThumbnail?.photoID == photo.id`일 때만 UIImage를 그린다. SwiftUI 구조적
/// identity가 보존된 채 부모가 다른 `photo`를 주입해도 — 슬롯 기반
/// `ForEach(0..<4, id: \.self)`에서 흔히 발생 — 옛 photoID의 Data는 렌더링 경로에서
/// 자동 차단된다.
///
/// `loadTask` 자체에도 `loadingPhotoID`라는 owner key를 둔다. 옛 photo의 task가 살아
/// 있을 때 `.onChange`가 늦거나 누락되더라도 두 갈래로 자가 치유된다:
/// (a) 다음 `startLoadIfNeeded` 진입에서 `loadingPhotoID != photo.id`인 task를 먼저
///     cancel하고 새 task를 띄운다.
/// (b) 옛 task가 await에서 깨어나 완료될 때, generation은 매칭이지만
///     `photo.id != self.photo.id`인 "stale owner" 케이스를 감지해 자기
///     loadTask/loadingPhotoID를 비우고 현재 self.photo 로드를 직접 kick한다.
/// 두 경로 모두 "stale image 대신 permanent placeholder"라는 dead-end를 차단한다.
/// `.onChange`는 storage/lifecycle 최적화 (옛 Data 즉시 해제) 용도일 뿐이고,
/// 렌더링 안전성과 progress 보장은 photoID 매칭과 owner-keyed task가 함께 책임진다.
struct ThumbnailView: View {
    @EnvironmentObject private var deps: DependencyContainer

    let photo: Photo

    @State private var loadedThumbnail: LoadedThumbnail?
    @State private var loadTask: Task<Void, Never>?
    @State private var loadingPhotoID: UUID?
    @State private var loadGeneration = 0

    var body: some View {
        Group {
            if
                let loaded = loadedThumbnail,
                loaded.photoID == photo.id,
                let image = UIImage(data: loaded.data)
            {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .onAppear {
            startLoadIfNeeded()
        }
        .onChange(of: photo.id) { _, _ in
            resetForCurrentPhoto()
        }
        .onDisappear {
            cancelLoad()
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: CornerRadius.sm, style: .continuous)
            .fill(Color.camorkFill.opacity(0.4))
    }

    @MainActor
    private func startLoadIfNeeded() {
        // 옛 photo 용도로 살아 있는 task가 있다면 새 photo 로드 전에 먼저 무효화한다.
        // 이 단계가 없으면 `.onChange`가 늦거나 누락된 경우 `loadTask == nil` 가드에
        // 막혀 새 photo 로드가 영원히 시작되지 않을 수 있다.
        if let loadingPhotoID, loadingPhotoID != photo.id {
            cancelLoad()
        }
        // 이미 현재 photo로 로드된 결과가 있거나 진행 중인 task가 있으면 중복 실행 금지.
        guard loadedThumbnail?.photoID != photo.id, loadTask == nil else { return }

        loadGeneration += 1
        let generation = loadGeneration
        // spawn 시점의 photo를 캡처. self.photo를 task 내부에서 다시 읽으면 photo가
        // 바뀐 뒤 늦게 시작되는 task가 새 photo를 한 번 더 fetch한 뒤 가드로 버리는
        // 낭비 디코드가 발생한다.
        let targetPhoto = photo
        loadingPhotoID = targetPhoto.id
        loadTask = Task {
            await load(photo: targetPhoto, generation: generation)
        }
    }

    @MainActor
    private func cancelLoad() {
        loadTask?.cancel()
        loadTask = nil
        loadingPhotoID = nil
        loadGeneration += 1
    }

    /// `photo.id`가 새 값으로 바뀐 직후 호출. 옛 photoID에 묶여 있던 Data를 즉시
    /// 해제하고 (메모리 압박 완화), `startLoadIfNeeded`에 진입해 옛 task를 cancel + 새
    /// task 시작 책임을 위임한다. 렌더링 안전성은 body의 photoID 매칭이 이미 보장하므로
    /// 이 함수는 storage/lifecycle 최적화에 가깝다.
    @MainActor
    private func resetForCurrentPhoto() {
        loadedThumbnail = nil
        startLoadIfNeeded()
    }

    @MainActor
    private func load(photo: Photo, generation: Int) async {
        let loadedData = try? await deps.mediaStorage.loadThumbnailData(for: photo)

        // 1) Newer-owner case: cancel 됐거나 generation이 바뀌었다 → 이미 다른 task가
        //    lifecycle ownership을 가져갔으므로 loadTask/loadingPhotoID를 건드리지 않는다.
        if Task.isCancelled || generation != loadGeneration {
            return
        }

        // 2) Current-owner-for-current-photo: 정상 경로. 결과를 publish하고 ownership 해제.
        if photo.id == self.photo.id {
            if let loadedData {
                loadedThumbnail = LoadedThumbnail(photoID: photo.id, data: loadedData)
            }
            loadTask = nil
            loadingPhotoID = nil
            return
        }

        // 3) Stale-owner-after-photo-swap: 이 task는 여전히 활성 owner인데
        //    (generation 매칭) self.photo가 바뀌었고 `.onChange`가 아직 cancel/start를
        //    돌리지 못한 중간 상태. 옛 photo의 결과를 폐기하고 ownership을 풀어준 뒤
        //    현재 self.photo 로드를 즉시 kick — `.onChange` 타이밍에 의존하지 않는 자가
        //    치유 경로. loadTask/loadingPhotoID를 nil 처리한 다음 startLoadIfNeeded에
        //    재진입하므로 가드의 owner-key cancel 분기도 그대로 통한다.
        loadTask = nil
        loadingPhotoID = nil
        startLoadIfNeeded()
    }
}

/// `(photoID, data)` 묶음. body 렌더링이 photoID 매칭에 키되어 있어, photo 변경 후에도
/// 옛 photoID의 Data가 새 photo 자리에 그려질 수 없다.
private struct LoadedThumbnail {
    let photoID: UUID
    let data: Data
}
