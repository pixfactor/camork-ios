import UIKit
import AVFoundation

enum ThumbnailGenerator {
    static func generateImageThumbnail(
        from imageData: Data,
        maxSize: CGSize = CGSize(width: 200, height: 200)
    ) -> Data? {
        guard let image = UIImage(data: imageData) else { return nil }
        let scaled = scaleImage(image, toFit: maxSize)
        return scaled.jpegData(compressionQuality: 0.7)
    }

    static func generateVideoThumbnail(
        from videoURL: URL,
        at time: CMTime = .zero,
        maxSize: CGSize = CGSize(width: 200, height: 200)
    ) -> Data? {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maxSize
        guard let cgImage = try? generator.copyCGImage(at: time, actualTime: nil) else { return nil }
        let image = UIImage(cgImage: cgImage)
        return image.jpegData(compressionQuality: 0.7)
    }

    private static func scaleImage(_ image: UIImage, toFit maxSize: CGSize) -> UIImage {
        let aspectRatio = image.size.width / image.size.height
        var targetSize: CGSize
        if aspectRatio > maxSize.width / maxSize.height {
            targetSize = CGSize(width: maxSize.width, height: maxSize.width / aspectRatio)
        } else {
            targetSize = CGSize(width: maxSize.height * aspectRatio, height: maxSize.height)
        }
        let renderer = UIGraphicsImageRenderer(size: targetSize)
        return renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: targetSize))
        }
    }
}
