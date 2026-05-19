import Testing
import Foundation
import CoreGraphics
import ImageIO
import UIKit
import UniformTypeIdentifiers
@testable import Camork

@Suite("ThumbnailGenerator")
struct ThumbnailGeneratorTests {

    @Test("generateBasic: 출력은 JPEG, 짧은 변이 shortSidePixels 목표값")
    func generateBasic() throws {
        let source = makeJPEGData(width: 800, height: 1200)
        let thumb = try ThumbnailGenerator.generate(from: source, shortSidePixels: 400)

        let cgSource = CGImageSourceCreateWithData(thumb as CFData, nil)
        #expect(cgSource != nil)
        let type = CGImageSourceGetType(cgSource!) as String?
        #expect(type == UTType.jpeg.identifier)

        let (w, h) = pixelSize(of: thumb)
        let shortSide = min(w, h)
        // ImageIO 다운스케일 라운딩 허용 ±1px
        #expect(abs(shortSide - 400) <= 1)
    }

    @Test("aspect ratio 유지 (square 1000×1000 → 400×400)")
    func aspectRatioSquare() throws {
        let source = makeJPEGData(width: 1000, height: 1000)
        let thumb = try ThumbnailGenerator.generate(from: source, shortSidePixels: 400)
        let (w, h) = pixelSize(of: thumb)
        #expect(abs(w - h) <= 1, "square 비율 깨짐 (w=\(w), h=\(h))")
        #expect(abs(w - 400) <= 1)
    }

    @Test("aspect ratio 유지 (portrait 800×1200 → 400×600)")
    func aspectRatioPortrait() throws {
        let source = makeJPEGData(width: 800, height: 1200)
        let thumb = try ThumbnailGenerator.generate(from: source, shortSidePixels: 400)
        let (w, h) = pixelSize(of: thumb)
        #expect(abs(w - 400) <= 1, "portrait 짧은 변 (w=\(w))")
        #expect(abs(h - 600) <= 2, "portrait 긴 변 (h=\(h))")
    }

    @Test("aspect ratio 유지 (landscape 1200×800 → 600×400)")
    func aspectRatioLandscape() throws {
        let source = makeJPEGData(width: 1200, height: 800)
        let thumb = try ThumbnailGenerator.generate(from: source, shortSidePixels: 400)
        let (w, h) = pixelSize(of: thumb)
        #expect(abs(h - 400) <= 1, "landscape 짧은 변 (h=\(h))")
        #expect(abs(w - 600) <= 2, "landscape 긴 변 (w=\(w))")
    }

    @Test("decode 실패: 4-byte fake data → ThumbnailGenerator.Error.decodeFailed")
    func decodeFailure() throws {
        let bogus = Data([0x01, 0x02, 0x03, 0x04])
        #expect(throws: ThumbnailGenerator.Error.decodeFailed) {
            _ = try ThumbnailGenerator.generate(from: bogus, shortSidePixels: 400)
        }
    }

    @Test("no upscale: 원본 short side ≤ target → 원본 픽셀 크기 유지")
    func noUpscale() throws {
        // 원본 100×200 (shortSide=100) — target 400보다 작음
        let source = makeJPEGData(width: 100, height: 200)
        let thumb = try ThumbnailGenerator.generate(from: source, shortSidePixels: 400)
        let (w, h) = pixelSize(of: thumb)
        #expect(w == 100, "upscale 발생 (w=\(w), expected 100)")
        #expect(h == 200, "upscale 발생 (h=\(h), expected 200)")
    }
}

// MARK: - Test helpers

private func makeJPEGData(width: Int, height: Int) -> Data {
    // scale = 1.0으로 고정해 point ≡ pixel을 보장 — 본 helper의 `width`/`height` 인자가
    // 실제 픽셀 dim과 정확히 일치하도록 (디바이스 UIScreen scale 영향 차단).
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1.0
    format.preferredRange = .standard
    let renderer = UIGraphicsImageRenderer(
        size: CGSize(width: width, height: height),
        format: format
    )
    let image = renderer.image { _ in
        UIColor.systemBlue.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: width, height: height))
    }
    return image.jpegData(compressionQuality: 1.0)!
}

private func pixelSize(of jpegData: Data) -> (Int, Int) {
    let source = CGImageSourceCreateWithData(jpegData as CFData, nil)!
    let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [CFString: Any]
    let w = props[kCGImagePropertyPixelWidth] as! Int
    let h = props[kCGImagePropertyPixelHeight] as! Int
    return (w, h)
}
