import Foundation
import ImageIO

/// Pure metadata sanitizer for share copies (Plan C Phase 4.1).
struct ShareSanitizer: Sendable {
    enum Error: Swift.Error, Sendable, Equatable {
        case decodeFailed
        case encodeFailed
    }

    /// Returns image data suitable for sharing.
    ///
    /// When `stripLocation` is false, the validated original data is returned unchanged.
    /// When true, ImageIO copies the source image while removing GPS metadata from both
    /// image properties and XMP tags.
    static func sanitize(
        data: Data,
        stripLocation: Bool
    ) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetCount(source) > 0 else {
            throw Error.decodeFailed
        }

        guard stripLocation else {
            return data
        }

        guard let type = CGImageSourceGetType(source) else {
            throw Error.decodeFailed
        }

        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            type,
            CGImageSourceGetCount(source),
            nil
        ) else {
            throw Error.encodeFailed
        }

        for index in 0..<CGImageSourceGetCount(source) {
            let properties = sanitizedProperties(from: source, at: index)
            CGImageDestinationAddImageFromSource(
                destination,
                source,
                index,
                properties as CFDictionary
            )
        }

        guard CGImageDestinationFinalize(destination) else {
            throw Error.encodeFailed
        }

        return output as Data
    }

    private static func sanitizedProperties(
        from source: CGImageSource,
        at index: Int
    ) -> [CFString: Any] {
        var properties = (
            CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any]
        ) ?? [:]
        properties[kCGImagePropertyGPSDictionary] = kCFNull

        if let metadata = CGImageSourceCopyMetadataAtIndex(source, index, nil),
           let sanitizedMetadata = sanitizedMetadata(metadata) {
            properties[kCGImageDestinationMetadata] = sanitizedMetadata
        }

        return properties
    }

    private static func sanitizedMetadata(
        _ metadata: CGImageMetadata
    ) -> CGImageMetadata? {
        guard let mutableMetadata = CGImageMetadataCreateMutableCopy(metadata) else {
            return nil
        }

        for path in gpsMetadataPaths(in: metadata) {
            CGImageMetadataRemoveTagWithPath(mutableMetadata, nil, path as CFString)
        }

        return mutableMetadata
    }

    private static func gpsMetadataPaths(in metadata: CGImageMetadata) -> [String] {
        var paths: [String] = []
        let options: [CFString: Any] = [
            kCGImageMetadataEnumerateRecursively: true
        ]

        CGImageMetadataEnumerateTagsUsingBlock(metadata, nil, options as CFDictionary) { path, tag in
            let pathString = path as String
            let name = CGImageMetadataTagCopyName(tag) as String? ?? ""
            if pathString.localizedCaseInsensitiveContains("GPS") ||
                name.localizedCaseInsensitiveContains("GPS") {
                paths.append(pathString)
            }
            return true
        }

        return paths
    }
}
