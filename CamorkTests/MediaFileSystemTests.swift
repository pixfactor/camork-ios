import Testing
import Foundation
@testable import Camork

@Suite("MediaFileSystem")
struct MediaFileSystemTests {

    @Test("staging write 후 final로 mv 성공")
    func stagingToFinalSuccess() throws {
        let fs = try MediaFileSystem(root: tempDir(), cachesRoot: tempDir())
        try fs.writeStaging(fileName: "abc.heic", data: Data([1, 2, 3]))
        try fs.moveStagingToFinal(fileName: "abc.heic")
        #expect(try fs.finalExists(fileName: "abc.heic"))
        #expect(try !fs.stagingExists(fileName: "abc.heic"))
    }

    @Test("staging cleanup")
    func stagingCleanup() throws {
        let fs = try MediaFileSystem(root: tempDir(), cachesRoot: tempDir())
        try fs.writeStaging(fileName: "abc.heic", data: Data([1, 2, 3]))
        try fs.removeStaging(fileName: "abc.heic")
        #expect(try !fs.stagingExists(fileName: "abc.heic"))
    }

    @Test("Media 디렉토리에 isExcludedFromBackup 플래그 적용")
    func excludedFromBackup() throws {
        let root = tempDir()
        _ = try MediaFileSystem(root: root, cachesRoot: tempDir())
        let values = try root.appendingPathComponent("Media")
            .resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test("legacy Application Support Thumbnails 디렉토리에도 isExcludedFromBackup 플래그 적용 (Plan B 잔재, Plan C는 cachesRoot/Thumbnails 사용)")
    func legacyApplicationSupportThumbnailsExcludedFromBackup() throws {
        let root = tempDir()
        _ = try MediaFileSystem(root: root, cachesRoot: tempDir())
        let values = try root.appendingPathComponent("Thumbnails")
            .resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test("removeFinal 후 finalExists 는 false")
    func removeFinalClears() throws {
        let fs = try MediaFileSystem(root: tempDir(), cachesRoot: tempDir())
        try fs.writeStaging(fileName: "abc.heic", data: Data([1, 2, 3]))
        try fs.moveStagingToFinal(fileName: "abc.heic")
        try fs.removeFinal(fileName: "abc.heic")
        #expect(try !fs.finalExists(fileName: "abc.heic"))
    }

    @Test("enumerateFinal 은 mv된 파일만 반환")
    func enumerateFinalListsFiles() throws {
        let fs = try MediaFileSystem(root: tempDir(), cachesRoot: tempDir())
        try fs.writeStaging(fileName: "a.heic", data: Data([1]))
        try fs.moveStagingToFinal(fileName: "a.heic")
        try fs.writeStaging(fileName: "b.heic", data: Data([2]))
        try fs.moveStagingToFinal(fileName: "b.heic")
        try fs.writeStaging(fileName: "still-staging.heic", data: Data([3]))

        let names = try fs.enumerateFinal().sorted()
        #expect(names == ["a.heic", "b.heic"])
    }

    // MARK: - Thumbnail cache (Plan C Phase 2.1)

    @Test("writeThumb + readThumb round-trip — 같은 Data 반환")
    func thumbRoundTrip() throws {
        let fs = try MediaFileSystem(root: tempDir(), cachesRoot: tempDir())
        let data = Data([0x01, 0x02, 0x03, 0x04])
        try fs.writeThumb(fileName: "abc.jpg", data: data)
        let read = try fs.readThumb(fileName: "abc.jpg")
        #expect(read == data)
    }

    @Test("removeThumb 후 readThumb은 throw (silent empty Data 반환 금지)")
    func thumbRemove() throws {
        let fs = try MediaFileSystem(root: tempDir(), cachesRoot: tempDir())
        try fs.writeThumb(fileName: "abc.jpg", data: Data([0x01]))
        try fs.removeThumb(fileName: "abc.jpg")
        #expect(throws: (any Error).self) {
            _ = try fs.readThumb(fileName: "abc.jpg")
        }
    }

    @Test("Thumbnails 디렉토리는 cachesRoot 아래 생성 (Library/Caches invariant)")
    func thumbDirCreatedUnderCaches() throws {
        let cachesRoot = tempDir()
        _ = try MediaFileSystem(root: tempDir(), cachesRoot: cachesRoot)
        let thumbDir = cachesRoot.appendingPathComponent("Thumbnails")
        var isDir: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: thumbDir.path, isDirectory: &isDir)
        #expect(exists)
        #expect(isDir.boolValue)
    }

    @Test("Data Protection — cachesRoot/Thumbnails 디렉토리 + writeThumb 파일 (실기기 enforcement, 시뮬레이터 tolerant)")
    func thumbDataProtection() throws {
        let cachesRoot = tempDir()
        let fs = try MediaFileSystem(root: tempDir(), cachesRoot: cachesRoot)

        let thumbDir = cachesRoot.appendingPathComponent("Thumbnails")
        let dirAttrs = try FileManager.default.attributesOfItem(atPath: thumbDir.path)
        let dirProtection = dirAttrs[.protectionKey] as? FileProtectionType

        try fs.writeThumb(fileName: "abc.jpg", data: Data([0x01, 0x02]))
        let fileAttrs = try FileManager.default.attributesOfItem(
            atPath: thumbDir.appendingPathComponent("abc.jpg").path
        )
        let fileProtection = fileAttrs[.protectionKey] as? FileProtectionType

        // 시뮬레이터: APFS sandbox는 Data Protection enforcement를 stub처리 — attributesOfItem
        // 이 .protectionKey를 nil로 반환할 수 있음. 본 테스트는 (a) 실기기에서 정확한 값을
        // 보장하고 (b) 시뮬레이터에서 attribute가 보이면 정확해야 한다는 contract로 표현.
        #if targetEnvironment(simulator)
        if let dirProtection {
            #expect(dirProtection == .completeUntilFirstUserAuthentication)
        }
        if let fileProtection {
            #expect(fileProtection == .completeUntilFirstUserAuthentication)
        }
        #else
        #expect(dirProtection == .completeUntilFirstUserAuthentication, "디렉토리 Data Protection 누락")
        #expect(fileProtection == .completeUntilFirstUserAuthentication, "writeThumb 파일 Data Protection 누락")
        #endif
    }
}

private func tempDir() -> URL {
    URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
}
