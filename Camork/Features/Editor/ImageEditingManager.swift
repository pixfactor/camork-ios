import UIKit
import CoreGraphics

enum ImageEditingManager {

    // MARK: - Crop

    /// Crops `image` to `rect`, where `rect` is in the image's coordinate space (pixels).
    static func cropImage(_ image: UIImage, to rect: CGRect) -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }

        // Normalize rect for the image orientation
        let normalizedRect = normalizedCropRect(rect, in: image)
        guard let croppedCG = cgImage.cropping(to: normalizedRect) else { return nil }
        return UIImage(cgImage: croppedCG, scale: image.scale, orientation: image.imageOrientation)
    }

    // MARK: - Rotate

    /// Rotates `image` by `degrees` (must be a multiple of 90).
    static func rotateImage(_ image: UIImage, by degrees: CGFloat) -> UIImage? {
        let normalizedDegrees = degrees.truncatingRemainder(dividingBy: 360)
        guard normalizedDegrees != 0 else { return image }

        let radians = normalizedDegrees * .pi / 180
        let originalSize = image.size

        // Calculate new bounding box
        let transform = CGAffineTransform(rotationAngle: radians)
        let rotatedRect = CGRect(origin: .zero, size: originalSize).applying(transform)
        let newSize = CGSize(width: abs(rotatedRect.width), height: abs(rotatedRect.height))

        let renderer = UIGraphicsImageRenderer(size: newSize)
        let rotated = renderer.image { ctx in
            let context = ctx.cgContext
            context.translateBy(x: newSize.width / 2, y: newSize.height / 2)
            context.rotate(by: radians)
            image.draw(in: CGRect(
                x: -originalSize.width / 2,
                y: -originalSize.height / 2,
                width: originalSize.width,
                height: originalSize.height
            ))
        }
        return rotated
    }

    // MARK: - Export

    static func jpegData(from image: UIImage, compressionQuality: CGFloat = 0.92) -> Data? {
        image.jpegData(compressionQuality: compressionQuality)
    }

    // MARK: - Private helpers

    /// Converts a rect expressed in the view's display coordinate space back to
    /// the CGImage's pixel coordinate space, accounting for image orientation.
    private static func normalizedCropRect(_ rect: CGRect, in image: UIImage) -> CGRect {
        let imageSize = image.size
        let scaleX = imageSize.width  / imageSize.width   // already in image points; keep scale
        let scaleY = imageSize.height / imageSize.height

        // rect is already expressed in image-size points, just clamp it
        let clamped = rect.intersection(CGRect(origin: .zero, size: imageSize))

        // Map to pixel coordinates
        let pixelScale = image.scale
        return CGRect(
            x: clamped.origin.x * pixelScale * scaleX,
            y: clamped.origin.y * pixelScale * scaleY,
            width: clamped.width * pixelScale * scaleX,
            height: clamped.height * pixelScale * scaleY
        )
    }
}
