import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Plan C Phase 2.2 — pure helper. 원본 HEIC/JPEG `Data`를 짧은 변 기준 다운스케일 후
/// JPEG quality 0.8로 인코딩. ImageIO `CGImageSourceCreateThumbnailAtIndex` 기반이라
/// off-main thread에서 호출해도 안전 (UIImage/UIScreen 미사용).
///
/// **API contract**:
/// - 입력 `shortSidePixels`는 픽셀 단위. 호출자가 `400 * Int(scale)` 형식으로 결정 —
///   본 helper는 UIScreen에 의존하지 않아 테스트 결정성 확보.
/// - **Upscale 방지**: 원본 short side가 target 픽셀 이하면 픽셀 크기 유지하고 JPEG로만
///   재인코딩 (소형 thumbnail이 원본보다 커지는 낭비 차단).
/// - **Aspect ratio 보존**: 짧은 변이 target에 맞춰지고 긴 변은 비율 유지.
/// - 잘못된 데이터(decode 불가) → `Error.decodeFailed`.
enum ThumbnailGenerator {
    enum Error: Swift.Error, Sendable, Equatable {
        case decodeFailed
        case encodeFailed
    }

    static func generate(from data: Data, shortSidePixels: Int) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw Error.decodeFailed
        }
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int,
              pixelWidth > 0, pixelHeight > 0 else {
            throw Error.decodeFailed
        }

        let sourceShortSide = min(pixelWidth, pixelHeight)
        let sourceLongSide = max(pixelWidth, pixelHeight)

        let cgImage: CGImage
        if sourceShortSide <= shortSidePixels {
            // No upscale — 원본 픽셀 그대로 decode
            guard let img = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
                throw Error.decodeFailed
            }
            cgImage = img
        } else {
            // 짧은 변을 target에 맞추되 ImageIO의 ThumbnailMaxPixelSize는 긴 변 기준이므로
            // 동일 비율로 환산한 긴 변 픽셀로 설정.
            let scale = Double(shortSidePixels) / Double(sourceShortSide)
            let targetLongSide = Int((Double(sourceLongSide) * scale).rounded())
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true,
                kCGImageSourceThumbnailMaxPixelSize: targetLongSide
            ]
            guard let img = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else {
                throw Error.decodeFailed
            }
            cgImage = img
        }

        let output = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(
            output,
            UTType.jpeg.identifier as CFString,
            1,
            nil
        ) else {
            throw Error.encodeFailed
        }
        let encodeOptions: [CFString: Any] = [
            kCGImageDestinationLossyCompressionQuality: 0.8
        ]
        CGImageDestinationAddImage(dest, cgImage, encodeOptions as CFDictionary)
        guard CGImageDestinationFinalize(dest) else {
            throw Error.encodeFailed
        }
        return output as Data
    }
}
