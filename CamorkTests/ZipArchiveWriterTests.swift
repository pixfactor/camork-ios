import Foundation
import Testing
@testable import Camork

@Suite("ZipArchiveWriter")
struct ZipArchiveWriterTests {
    @Test("writes a store-method zip with local header, central directory, and EOCD")
    func writesZipFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("zip")
        defer { try? FileManager.default.removeItem(at: url) }

        try ZipArchiveWriter.write(
            entries: [
                ZipArchiveEntry(path: "metadata.json", data: Data(#"{"ok":true}"#.utf8)),
                ZipArchiveEntry(path: "Media/photo.heic", data: Data([0x01, 0x02]))
            ],
            to: url
        )

        let data = try Data(contentsOf: url)
        #expect(data.count > 80)
        #expect(data.prefix(4) == Data([0x50, 0x4b, 0x03, 0x04]))
        #expect(data.containsSubsequence(Data("metadata.json".utf8)))
        #expect(data.containsSubsequence(Data("Media/photo.heic".utf8)))
        #expect(data.suffix(22).prefix(4) == Data([0x50, 0x4b, 0x05, 0x06]))
    }

    @Test("rejects path traversal entries")
    func rejectsTraversal() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("zip")

        #expect(throws: ZipArchiveError.invalidEntryName) {
            try ZipArchiveWriter.write(
                entries: [ZipArchiveEntry(path: "../metadata.json", data: Data())],
                to: url
            )
        }
    }
}

private extension Data {
    func containsSubsequence(_ needle: Data) -> Bool {
        guard !needle.isEmpty, needle.count <= count else { return false }
        return self.withUnsafeBytes { haystackRaw in
            needle.withUnsafeBytes { needleRaw in
                guard let haystackBase = haystackRaw.baseAddress,
                      let needleBase = needleRaw.baseAddress
                else { return false }
                for offset in 0...(count - needle.count) {
                    if memcmp(haystackBase.advanced(by: offset), needleBase, needle.count) == 0 {
                        return true
                    }
                }
                return false
            }
        }
    }
}
