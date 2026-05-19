import Testing
import Foundation
@testable import Camork

@Suite("MediaFileSystem")
struct MediaFileSystemTests {

    @Test("staging write 후 final로 mv 성공")
    func stagingToFinalSuccess() throws {
        let fs = try MediaFileSystem(root: tempDir())
        try fs.writeStaging(fileName: "abc.heic", data: Data([1, 2, 3]))
        try fs.moveStagingToFinal(fileName: "abc.heic")
        #expect(try fs.finalExists(fileName: "abc.heic"))
        #expect(try !fs.stagingExists(fileName: "abc.heic"))
    }

    @Test("staging cleanup")
    func stagingCleanup() throws {
        let fs = try MediaFileSystem(root: tempDir())
        try fs.writeStaging(fileName: "abc.heic", data: Data([1, 2, 3]))
        try fs.removeStaging(fileName: "abc.heic")
        #expect(try !fs.stagingExists(fileName: "abc.heic"))
    }

    @Test("Media 디렉토리에 isExcludedFromBackup 플래그 적용")
    func excludedFromBackup() throws {
        let root = tempDir()
        _ = try MediaFileSystem(root: root)
        let values = try root.appendingPathComponent("Media")
            .resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test("Thumbnails 디렉토리에도 isExcludedFromBackup 플래그 적용")
    func thumbnailsExcludedFromBackup() throws {
        let root = tempDir()
        _ = try MediaFileSystem(root: root)
        let values = try root.appendingPathComponent("Thumbnails")
            .resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test("removeFinal 후 finalExists 는 false")
    func removeFinalClears() throws {
        let fs = try MediaFileSystem(root: tempDir())
        try fs.writeStaging(fileName: "abc.heic", data: Data([1, 2, 3]))
        try fs.moveStagingToFinal(fileName: "abc.heic")
        try fs.removeFinal(fileName: "abc.heic")
        #expect(try !fs.finalExists(fileName: "abc.heic"))
    }

    @Test("enumerateFinal 은 mv된 파일만 반환")
    func enumerateFinalListsFiles() throws {
        let fs = try MediaFileSystem(root: tempDir())
        try fs.writeStaging(fileName: "a.heic", data: Data([1]))
        try fs.moveStagingToFinal(fileName: "a.heic")
        try fs.writeStaging(fileName: "b.heic", data: Data([2]))
        try fs.moveStagingToFinal(fileName: "b.heic")
        try fs.writeStaging(fileName: "still-staging.heic", data: Data([3]))

        let names = try fs.enumerateFinal().sorted()
        #expect(names == ["a.heic", "b.heic"])
    }
}

private func tempDir() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
}
