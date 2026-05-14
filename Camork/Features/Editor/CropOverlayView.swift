import SwiftUI

// MARK: - Aspect Ratio Preset

enum AspectRatioPreset: String, CaseIterable {
    case free  = "자유"
    case square = "1:1"
    case fourThree = "4:3"
    case sixteenNine = "16:9"

    var ratio: CGFloat? {
        switch self {
        case .free:        return nil
        case .square:      return 1.0
        case .fourThree:   return 4.0 / 3.0
        case .sixteenNine: return 16.0 / 9.0
        }
    }
}

// MARK: - CropOverlayView

struct CropOverlayView: View {
    /// Crop rect in the parent view's coordinate space (points).
    @Binding var cropRect: CGRect
    let bounds: CGRect          // available area the crop rect must stay within
    let minSize: CGFloat = 50

    @State private var activeHandle: DragHandle? = nil

    enum DragHandle {
        case topLeft, topRight, bottomLeft, bottomRight
        case top, bottom, left, right
        case move
    }

    var body: some View {
        ZStack {
            // Semi-transparent dark overlay outside crop area
            Color.black.opacity(0.5)
                .mask(
                    Rectangle()
                        .overlay(
                            Rectangle()
                                .frame(width: cropRect.width, height: cropRect.height)
                                .offset(x: cropRect.midX - bounds.width / 2,
                                        y: cropRect.midY - bounds.height / 2)
                                .blendMode(.destinationOut)
                        )
                        .compositingGroup()
                )

            // Crop border
            Rectangle()
                .stroke(Color.white, lineWidth: 1.5)
                .frame(width: cropRect.width, height: cropRect.height)
                .position(x: cropRect.midX, y: cropRect.midY)

            // Grid lines (rule-of-thirds)
            gridLines

            // Dimension label
            dimensionLabel

            // Corner handles
            cornerHandle(.topLeft,     at: CGPoint(x: cropRect.minX, y: cropRect.minY))
            cornerHandle(.topRight,    at: CGPoint(x: cropRect.maxX, y: cropRect.minY))
            cornerHandle(.bottomLeft,  at: CGPoint(x: cropRect.minX, y: cropRect.maxY))
            cornerHandle(.bottomRight, at: CGPoint(x: cropRect.maxX, y: cropRect.maxY))

            // Edge handles
            edgeHandle(.top,    at: CGPoint(x: cropRect.midX, y: cropRect.minY))
            edgeHandle(.bottom, at: CGPoint(x: cropRect.midX, y: cropRect.maxY))
            edgeHandle(.left,   at: CGPoint(x: cropRect.minX, y: cropRect.midY))
            edgeHandle(.right,  at: CGPoint(x: cropRect.maxX, y: cropRect.midY))

            // Move gesture (inner area)
            Rectangle()
                .fill(Color.clear)
                .frame(width: max(cropRect.width - 40, 0),
                       height: max(cropRect.height - 40, 0))
                .position(x: cropRect.midX, y: cropRect.midY)
                .gesture(moveGesture)
                .contentShape(Rectangle())
        }
        .frame(width: bounds.width, height: bounds.height)
    }

    // MARK: - Grid Lines

    private var gridLines: some View {
        let w = cropRect.width
        let h = cropRect.height
        return ZStack {
            // Vertical thirds
            Rectangle()
                .fill(Color.white.opacity(0.35))
                .frame(width: 0.5, height: h)
                .position(x: cropRect.minX + w / 3, y: cropRect.midY)
            Rectangle()
                .fill(Color.white.opacity(0.35))
                .frame(width: 0.5, height: h)
                .position(x: cropRect.minX + w * 2 / 3, y: cropRect.midY)
            // Horizontal thirds
            Rectangle()
                .fill(Color.white.opacity(0.35))
                .frame(width: w, height: 0.5)
                .position(x: cropRect.midX, y: cropRect.minY + h / 3)
            Rectangle()
                .fill(Color.white.opacity(0.35))
                .frame(width: w, height: 0.5)
                .position(x: cropRect.midX, y: cropRect.minY + h * 2 / 3)
        }
    }

    // MARK: - Dimension Label

    private var dimensionLabel: some View {
        // Show crop width × height in points
        let w = Int(cropRect.width)
        let h = Int(cropRect.height)
        return Text("\(w) × \(h)")
            .font(.caption2.monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.55), in: Capsule())
            .position(x: cropRect.midX, y: cropRect.minY - 16)
    }

    // MARK: - Corner Handles

    private func cornerHandle(_ handle: DragHandle, at point: CGPoint) -> some View {
        let size: CGFloat = 22
        return Rectangle()
            .fill(Color.clear)
            .frame(width: size, height: size)
            .overlay(cornerShape(handle))
            .position(point)
            .gesture(dragGesture(for: handle))
    }

    private func cornerShape(_ handle: DragHandle) -> some View {
        let len: CGFloat = 18
        let w: CGFloat = 3
        return ZStack {
            // horizontal arm
            Rectangle()
                .fill(Color.white)
                .frame(width: len / 2 + w / 2, height: w)
                .offset(x: (handle == .topLeft || handle == .bottomLeft) ? (len / 4) : -(len / 4))
            // vertical arm
            Rectangle()
                .fill(Color.white)
                .frame(width: w, height: len / 2 + w / 2)
                .offset(y: (handle == .topLeft || handle == .topRight) ? (len / 4) : -(len / 4))
        }
    }

    // MARK: - Edge Handles

    private func edgeHandle(_ handle: DragHandle, at point: CGPoint) -> some View {
        let isHorizontal = (handle == .top || handle == .bottom)
        return Capsule()
            .fill(Color.white.opacity(0.8))
            .frame(
                width:  isHorizontal ? 44 : 4,
                height: isHorizontal ? 4  : 44
            )
            .position(point)
            .gesture(dragGesture(for: handle))
    }

    // MARK: - Drag Gestures

    private func dragGesture(for handle: DragHandle) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("cropOverlay"))
            .onChanged { value in
                updateCropRect(handle: handle, translation: value.translation)
            }
    }

    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .named("cropOverlay"))
            .onChanged { value in
                let dx = value.translation.width
                let dy = value.translation.height
                var newRect = cropRect.offsetBy(dx: dx, dy: dy)
                // Clamp to bounds
                newRect.origin.x = max(bounds.minX, min(newRect.origin.x, bounds.maxX - newRect.width))
                newRect.origin.y = max(bounds.minY, min(newRect.origin.y, bounds.maxY - newRect.height))
                cropRect = newRect
            }
    }

    private func updateCropRect(handle: DragHandle, translation: CGSize) {
        var r = cropRect
        let dx = translation.width
        let dy = translation.height

        switch handle {
        case .topLeft:
            r.origin.x = min(r.maxX - minSize, max(bounds.minX, r.origin.x + dx))
            r.origin.y = min(r.maxY - minSize, max(bounds.minY, r.origin.y + dy))
            r.size.width  = cropRect.maxX - r.origin.x
            r.size.height = cropRect.maxY - r.origin.y

        case .topRight:
            r.origin.y = min(r.maxY - minSize, max(bounds.minY, r.origin.y + dy))
            r.size.width  = max(minSize, min(bounds.maxX - r.origin.x, r.width + dx))
            r.size.height = cropRect.maxY - r.origin.y

        case .bottomLeft:
            r.origin.x = min(r.maxX - minSize, max(bounds.minX, r.origin.x + dx))
            r.size.width  = cropRect.maxX - r.origin.x
            r.size.height = max(minSize, min(bounds.maxY - r.origin.y, r.height + dy))

        case .bottomRight:
            r.size.width  = max(minSize, min(bounds.maxX - r.origin.x, r.width + dx))
            r.size.height = max(minSize, min(bounds.maxY - r.origin.y, r.height + dy))

        case .top:
            r.origin.y = min(r.maxY - minSize, max(bounds.minY, r.origin.y + dy))
            r.size.height = cropRect.maxY - r.origin.y

        case .bottom:
            r.size.height = max(minSize, min(bounds.maxY - r.origin.y, r.height + dy))

        case .left:
            r.origin.x = min(r.maxX - minSize, max(bounds.minX, r.origin.x + dx))
            r.size.width = cropRect.maxX - r.origin.x

        case .right:
            r.size.width = max(minSize, min(bounds.maxX - r.origin.x, r.width + dx))

        case .move:
            break
        }

        cropRect = r
    }
}
