import SwiftUI
import SwiftData
import UIKit

// MARK: - Editing Mode

private enum EditMode {
    case crop, rotate
}

// MARK: - PhotoEditorView

struct PhotoEditorView: View {
    let item: MediaItem

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    // Image state
    @State private var originalImage: UIImage?
    @State private var previewImage: UIImage?
    @State private var isLoading = true

    // Edit mode
    @State private var editMode: EditMode = .crop

    // Crop state
    @State private var cropRect: CGRect = .zero
    @State private var imageFrame: CGRect = .zero   // rendered image frame inside the view

    // Rotate state
    @State private var cumulativeRotation: CGFloat = 0   // degrees (0, 90, 180, 270)

    // Aspect ratio
    @State private var aspectPreset: AspectRatioPreset = .free

    // Save alert
    @State private var showingSaveAlert = false
    @State private var isSaving = false
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if isLoading {
                    ProgressView()
                        .tint(.white)
                } else if let preview = previewImage {
                    VStack(spacing: 0) {
                        // Image + crop overlay area
                        GeometryReader { geo in
                            let frame = geo.frame(in: .local)
                            ZStack {
                                Image(uiImage: preview)
                                    .resizable()
                                    .scaledToFit()
                                    .frame(maxWidth: frame.width, maxHeight: frame.height)
                                    .background(
                                        GeometryReader { imgGeo in
                                            Color.clear.onAppear {
                                                imageFrame = imgGeo.frame(in: .local)
                                                resetCropRect(for: imgGeo.size)
                                            }
                                            .onChange(of: preview.size) { _, _ in
                                                imageFrame = imgGeo.frame(in: .local)
                                                resetCropRect(for: imgGeo.size)
                                            }
                                        }
                                    )

                                if editMode == .crop {
                                    CropOverlayView(
                                        cropRect: $cropRect,
                                        bounds: imageFrame
                                    )
                                    .coordinateSpace(name: "cropOverlay")
                                    .frame(width: frame.width, height: frame.height)
                                }
                            }
                            .frame(width: frame.width, height: frame.height)
                        }

                        // Controls area
                        VStack(spacing: 0) {
                            if editMode == .crop {
                                aspectRatioBar
                            } else {
                                rotateBar
                            }
                            bottomToolbar
                        }
                        .background(Color.black)
                    }
                } else {
                    Text("이미지를 불러올 수 없습니다")
                        .foregroundStyle(.secondary)
                }

                if isSaving {
                    Color.black.opacity(0.4).ignoresSafeArea()
                    ProgressView("저장 중...")
                        .tint(.white)
                        .foregroundStyle(.white)
                }
            }
            .navigationTitle("편집")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("취소") { dismiss() }
                        .foregroundStyle(.white)
                }
            }
            .alert("저장 방식 선택", isPresented: $showingSaveAlert) {
                Button("덮어쓰기") { performSave(asNewCopy: false) }
                Button("사본으로 저장") { performSave(asNewCopy: true) }
                Button("취소", role: .cancel) {}
            } message: {
                Text("편집한 이미지를 어떻게 저장할까요?")
            }
            .alert("저장 실패", isPresented: .constant(saveError != nil)) {
                Button("확인") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
        .task {
            await loadImage()
        }
    }

    // MARK: - Aspect Ratio Bar

    private var aspectRatioBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(AspectRatioPreset.allCases, id: \.self) { preset in
                    Button {
                        aspectPreset = preset
                        applyAspectRatio(preset)
                    } label: {
                        Text(preset.rawValue)
                            .font(.caption)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(
                                aspectPreset == preset
                                    ? Color.yellow
                                    : Color.white.opacity(0.15),
                                in: Capsule()
                            )
                            .foregroundStyle(
                                aspectPreset == preset ? Color.black : Color.white
                            )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - Rotate Bar

    private var rotateBar: some View {
        HStack(spacing: 32) {
            Button {
                applyRotation(-90)
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "rotate.left")
                        .font(.title2)
                    Text("왼쪽 회전")
                        .font(.caption2)
                }
                .foregroundStyle(.white)
            }

            Button {
                applyRotation(90)
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "rotate.right")
                        .font(.title2)
                    Text("오른쪽 회전")
                        .font(.caption2)
                }
                .foregroundStyle(.white)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
    }

    // MARK: - Bottom Toolbar

    private var bottomToolbar: some View {
        HStack {
            // Crop mode button
            Button {
                editMode = .crop
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "crop")
                        .font(.title2)
                    Text("자르기")
                        .font(.caption2)
                }
                .foregroundStyle(editMode == .crop ? .yellow : .white)
            }
            .frame(maxWidth: .infinity)

            // Rotate mode button
            Button {
                editMode = .rotate
            } label: {
                VStack(spacing: 4) {
                    Image(systemName: "rotate.right")
                        .font(.title2)
                    Text("회전")
                        .font(.caption2)
                }
                .foregroundStyle(editMode == .rotate ? .yellow : .white)
            }
            .frame(maxWidth: .infinity)

            // Save button
            Button {
                showingSaveAlert = true
            } label: {
                Text("저장")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.yellow, in: Capsule())
            }
            .frame(maxWidth: .infinity)
            .disabled(isSaving)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
        .padding(.bottom, 8)
    }

    // MARK: - Load Image

    private func loadImage() async {
        let url = FileStorageManager.shared.getMediaURL(fileName: item.fileName)
        guard let data = try? Data(contentsOf: url),
              let img = UIImage(data: data) else {
            isLoading = false
            return
        }
        originalImage = img
        previewImage = img
        isLoading = false
    }

    // MARK: - Crop Rect Reset

    private func resetCropRect(for size: CGSize) {
        cropRect = CGRect(origin: .zero, size: size)
        imageFrame = CGRect(origin: .zero, size: size)
    }

    // MARK: - Aspect Ratio

    private func applyAspectRatio(_ preset: AspectRatioPreset) {
        guard let ratio = preset.ratio else { return } // free: do nothing
        let bounds = imageFrame
        let maxW = bounds.width
        let maxH = bounds.height

        var newW: CGFloat
        var newH: CGFloat

        if maxW / ratio <= maxH {
            newW = maxW
            newH = maxW / ratio
        } else {
            newH = maxH
            newW = maxH * ratio
        }

        cropRect = CGRect(
            x: (maxW - newW) / 2,
            y: (maxH - newH) / 2,
            width: newW,
            height: newH
        )
    }

    // MARK: - Rotation

    private func applyRotation(_ degrees: CGFloat) {
        guard let current = previewImage else { return }
        guard let rotated = ImageEditingManager.rotateImage(current, by: degrees) else { return }
        cumulativeRotation += degrees
        previewImage = rotated
        // Reset crop rect for new dimensions
        resetCropRect(for: CGSize(
            width: imageFrame.height,  // swap dimensions after 90° rotation
            height: imageFrame.width
        ))
    }

    // MARK: - Save

    private func performSave(asNewCopy: Bool) {
        guard let original = originalImage,
              let preview = previewImage else { return }

        isSaving = true

        Task {
            do {
                // 1. Apply rotation to original image
                let rotated: UIImage
                if cumulativeRotation != 0 {
                    rotated = ImageEditingManager.rotateImage(original, by: cumulativeRotation) ?? original
                } else {
                    rotated = original
                }

                // 2. Apply crop
                let finalImage: UIImage
                if cropRect != CGRect(origin: .zero, size: imageFrame.size) {
                    // Map cropRect (view points) to image pixel coordinates
                    let scaleX = rotated.size.width  / imageFrame.width
                    let scaleY = rotated.size.height / imageFrame.height
                    let pixelRect = CGRect(
                        x: cropRect.origin.x * scaleX,
                        y: cropRect.origin.y * scaleY,
                        width: cropRect.width  * scaleX,
                        height: cropRect.height * scaleY
                    )
                    finalImage = ImageEditingManager.cropImage(rotated, to: pixelRect) ?? rotated
                } else {
                    finalImage = rotated
                }

                // 3. Export to JPEG
                guard let jpegData = ImageEditingManager.jpegData(from: finalImage) else {
                    throw NSError(domain: "PhotoEditor", code: 1,
                                  userInfo: [NSLocalizedDescriptionKey: "JPEG 변환 실패"])
                }

                // 4. Generate thumbnail
                let thumbData = ThumbnailGenerator.generateImageThumbnail(from: jpegData)

                if asNewCopy {
                    // Save as new file
                    let newFileName = FileStorageManager.shared.generateUniqueFileName(extension: "jpg")
                    let newThumbName = FileStorageManager.shared.generateUniqueFileName(extension: "jpg")

                    _ = try await FileStorageManager.shared.saveMedia(data: jpegData, fileName: newFileName)
                    if let thumbData {
                        _ = try await FileStorageManager.shared.saveMedia(data: thumbData, fileName: newThumbName)
                    }

                    let newItem = MediaItem(
                        mediaType: .photo,
                        fileName: newFileName,
                        thumbnailFileName: newThumbName,
                        capturedAt: .now,
                        latitude: item.latitude,
                        longitude: item.longitude,
                        folder: item.folder
                    )
                    modelContext.insert(newItem)
                    try? modelContext.save()
                } else {
                    // Overwrite existing file
                    _ = try await FileStorageManager.shared.saveMedia(data: jpegData, fileName: item.fileName)
                    if let thumbData {
                        _ = try await FileStorageManager.shared.saveMedia(
                            data: thumbData,
                            fileName: item.thumbnailFileName
                        )
                    }
                    // Invalidate thumbnail cache so the updated image is reloaded
                    await ThumbnailCache.shared.invalidate(for: item.thumbnailFileName)
                }

                await MainActor.run {
                    isSaving = false
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    isSaving = false
                    saveError = error.localizedDescription
                }
            }
        }
    }
}
