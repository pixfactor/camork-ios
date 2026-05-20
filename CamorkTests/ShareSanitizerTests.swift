import CoreGraphics
import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import Camork

@Suite("ShareSanitizer")
struct ShareSanitizerTests {
    @Test("location ON: GPS dict 유지")
    func locationKeepsGPS() throws {
        let input = makeJPEGData()

        let output = try ShareSanitizer.sanitize(data: input, stripLocation: false)
        let props = properties(of: output)

        #expect(props[kCGImagePropertyGPSDictionary as String] != nil)
        #expect(metadataContainsGPS(output))
    }

    @Test("location OFF: GPS dict 제거 (EXIF+XMP 양쪽)")
    func locationStripsGPS() throws {
        let input = makeJPEGData()
        #expect(properties(of: input)[kCGImagePropertyGPSDictionary as String] != nil)
        #expect(metadataContainsGPS(input))

        let output = try ShareSanitizer.sanitize(data: input, stripLocation: true)
        let props = properties(of: output)

        #expect(props[kCGImagePropertyGPSDictionary as String] == nil)
        #expect(!metadataContainsGPS(output))
    }

    @Test("orientation 메타 보존 (90도 회전 입력 → 출력 동일)")
    func orientationPreserved() throws {
        let input = makeJPEGData()

        let output = try ShareSanitizer.sanitize(data: input, stripLocation: true)
        let props = properties(of: output)

        #expect(props[kCGImagePropertyOrientation as String] as? Int == 6)
    }

    @Test("DateTimeOriginal 보존 (location 토글과 무관)")
    func dateTimeOriginalPreserved() throws {
        let input = makeJPEGData()

        let stripped = try ShareSanitizer.sanitize(data: input, stripLocation: true)
        let kept = try ShareSanitizer.sanitize(data: input, stripLocation: false)

        #expect(dateTimeOriginal(of: stripped) == "2026:05:19 14:30:00")
        #expect(dateTimeOriginal(of: kept) == "2026:05:19 14:30:00")
    }

    @Test("ICC color profile 보존")
    func colorProfilePreserved() throws {
        let input = makeJPEGData()
        let inputProps = properties(of: input)

        let output = try ShareSanitizer.sanitize(data: input, stripLocation: true)
        let outputProps = properties(of: output)

        #expect(outputProps[kCGImagePropertyColorModel as String] as? String == inputProps[kCGImagePropertyColorModel as String] as? String)
        #expect(outputProps[kCGImagePropertyProfileName as String] as? String == inputProps[kCGImagePropertyProfileName as String] as? String)
    }

    /// Production captures HEIC (`MediaStorage.saveCapture` writes
    /// `<uuid>.heic`), so `CGImageSourceGetType(source)` returns `public.heic`
    /// and `ShareSanitizer` re-encodes through the HEIC destination path.
    /// JPEG-only fixtures left that branch unverified; this case pins:
    /// - GPS dictionary is removed when `stripLocation == true`
    /// - DateTimeOriginal and orientation survive the round trip
    @Test("HEIC location OFF: GPS dict 제거 + DateTimeOriginal/orientation 보존")
    func heicStripsGPSAndPreservesNonGPSMeta() throws {
        let input = makeHEICData()
        #expect(properties(of: input)[kCGImagePropertyGPSDictionary as String] != nil)
        #expect(dateTimeOriginal(of: input) == "2026:05:19 14:30:00")
        #expect(properties(of: input)[kCGImagePropertyOrientation as String] as? Int == 6)

        let output = try ShareSanitizer.sanitize(data: input, stripLocation: true)
        let outputProps = properties(of: output)

        #expect(outputProps[kCGImagePropertyGPSDictionary as String] == nil)
        #expect(!metadataContainsGPS(output))
        #expect(dateTimeOriginal(of: output) == "2026:05:19 14:30:00")
        #expect(outputProps[kCGImagePropertyOrientation as String] as? Int == 6)
    }
}

// MARK: - Test helpers

private func makeJPEGData() -> Data {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1.0
    format.preferredRange = .standard
    let renderer = UIGraphicsImageRenderer(
        size: CGSize(width: 16, height: 12),
        format: format
    )
    let image = renderer.image { _ in
        UIColor.systemGreen.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: 16, height: 12))
    }

    let output = NSMutableData()
    let destination = CGImageDestinationCreateWithData(
        output,
        UTType.jpeg.identifier as CFString,
        1,
        nil
    )!

    let exif: [String: Any] = [
        kCGImagePropertyExifDateTimeOriginal as String: "2026:05:19 14:30:00"
    ]
    let gps: [String: Any] = [
        kCGImagePropertyGPSLatitude as String: 37.3317,
        kCGImagePropertyGPSLatitudeRef as String: "N",
        kCGImagePropertyGPSLongitude as String: 122.0307,
        kCGImagePropertyGPSLongitudeRef as String: "W"
    ]
    let metadata = makeXMPGPSMetadata()
    let properties: [CFString: Any] = [
        kCGImagePropertyOrientation: 6,
        kCGImagePropertyExifDictionary: exif,
        kCGImagePropertyGPSDictionary: gps,
        kCGImageDestinationMetadata: metadata
    ]

    CGImageDestinationAddImage(destination, image.cgImage!, properties as CFDictionary)
    precondition(CGImageDestinationFinalize(destination))
    return output as Data
}

/// HEIC counterpart of `makeJPEGData`. Encodes a tiny image via the HEIC
/// destination so `CGImageSourceGetType(source)` returns `public.heic` and
/// `ShareSanitizer` exercises the HEIC re-encode path that production captures
/// land on.
private func makeHEICData() -> Data {
    let format = UIGraphicsImageRendererFormat()
    format.scale = 1.0
    format.preferredRange = .standard
    let renderer = UIGraphicsImageRenderer(
        size: CGSize(width: 16, height: 12),
        format: format
    )
    let image = renderer.image { _ in
        UIColor.systemOrange.setFill()
        UIRectFill(CGRect(x: 0, y: 0, width: 16, height: 12))
    }

    let output = NSMutableData()
    guard let destination = CGImageDestinationCreateWithData(
        output,
        UTType.heic.identifier as CFString,
        1,
        nil
    ) else {
        preconditionFailure("HEIC destination unavailable on this platform")
    }

    let exif: [String: Any] = [
        kCGImagePropertyExifDateTimeOriginal as String: "2026:05:19 14:30:00"
    ]
    let gps: [String: Any] = [
        kCGImagePropertyGPSLatitude as String: 37.3317,
        kCGImagePropertyGPSLatitudeRef as String: "N",
        kCGImagePropertyGPSLongitude as String: 122.0307,
        kCGImagePropertyGPSLongitudeRef as String: "W"
    ]
    let properties: [CFString: Any] = [
        kCGImagePropertyOrientation: 6,
        kCGImagePropertyExifDictionary: exif,
        kCGImagePropertyGPSDictionary: gps,
        kCGImageDestinationMetadata: makeXMPGPSMetadata()
    ]

    CGImageDestinationAddImage(destination, image.cgImage!, properties as CFDictionary)
    precondition(CGImageDestinationFinalize(destination))
    return output as Data
}

private func makeXMPGPSMetadata() -> CGImageMetadata {
    let metadata = CGImageMetadataCreateMutable()
    let namespace = "http://ns.adobe.com/exif/1.0/" as CFString
    let prefix = "exif" as CFString
    precondition(CGImageMetadataRegisterNamespaceForPrefix(metadata, namespace, prefix, nil))
    precondition(CGImageMetadataSetValueWithPath(metadata, nil, "exif:GPSLatitude" as CFString, 37.3317 as NSNumber))
    precondition(CGImageMetadataSetValueWithPath(metadata, nil, "exif:GPSLongitude" as CFString, 122.0307 as NSNumber))
    return metadata
}

private func properties(of data: Data) -> [String: Any] {
    let source = CGImageSourceCreateWithData(data as CFData, nil)!
    return CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as! [String: Any]
}

private func dateTimeOriginal(of data: Data) -> String? {
    let exif = properties(of: data)[kCGImagePropertyExifDictionary as String] as? [String: Any]
    return exif?[kCGImagePropertyExifDateTimeOriginal as String] as? String
}

private func metadataContainsGPS(_ data: Data) -> Bool {
    let source = CGImageSourceCreateWithData(data as CFData, nil)!
    guard let metadata = CGImageSourceCopyMetadataAtIndex(source, 0, nil) else {
        return false
    }

    var found = false
    let options: [CFString: Any] = [
        kCGImageMetadataEnumerateRecursively: true
    ]
    CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, options as CFDictionary) { path, tag in
        let pathString = path as String
        let name = CGImageMetadataTagCopyName(tag) as String? ?? ""
        if pathString.localizedCaseInsensitiveContains("GPS") ||
            name.localizedCaseInsensitiveContains("GPS") {
            found = true
            return false
        }
        return true
    }
    return found
}
