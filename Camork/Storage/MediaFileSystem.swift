import Foundation

/// `FileOps`의 production 구현.
///
/// 두 디렉토리 base를 사용:
/// - `root` (보통 `Library/Application Support/Camork/`): media + DB metadata 영속.
///   `Media/`, `Media/.staging/`, `Thumbnails/`(Plan B 잔재, Plan C 이후 미사용) 생성.
///   `isExcludedFromBackup = true` + Data Protection 적용 (ADR #12).
/// - `cachesRoot` (보통 `Library/Caches/Camork/`): thumbnail 캐시 영속 (Plan C
///   Phase 2.1). `Library/Caches/`는 iOS가 backup에서 자동 제외하므로
///   `isExcludedFromBackup` flag는 불필요하지만 Data Protection은 디렉토리 + write
///   options 양쪽에 명시 적용.
///
/// v1.2 C5: `init` throw — bootstrap 에러를 swallow하지 않는다 (silent 부분 부트스트랩
/// 상태로 동작하면 capture-save가 mv fail로 끝없이 재시도하는 failure mode 가능).
///
/// v1.3 C3 + v1.4 C2: 단일 canonical bootstrap (중복 sample 제거).
struct MediaFileSystem: FileOps {
    let root: URL
    let cachesRoot: URL

    init(root: URL, cachesRoot: URL) throws {
        self.root = root
        self.cachesRoot = cachesRoot
        try Self.bootstrap(root: root, cachesRoot: cachesRoot)
    }

    /// media root와 cachesRoot 각각의 디렉토리를 생성하고 적절한 보호 속성을 적용.
    static func bootstrap(root: URL, cachesRoot: URL) throws {
        // Application Support 하위: backup 제외 + Data Protection
        for sub in ["Media", "Media/.staging", "Thumbnails"] {
            var dir = root.appendingPathComponent(sub, isDirectory: true)
            try FileManager.default.createDirectory(
                at: dir,
                withIntermediateDirectories: true
            )
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try dir.setResourceValues(values)
            try FileManager.default.setAttributes(
                [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                ofItemAtPath: dir.path
            )
        }

        // Library/Caches/Camork/Thumbnails: iOS가 backup에서 자동 제외하므로
        // isExcludedFromBackup 불필요. Data Protection은 명시 적용.
        let thumbDir = cachesRoot.appendingPathComponent("Thumbnails", isDirectory: true)
        try FileManager.default.createDirectory(
            at: thumbDir,
            withIntermediateDirectories: true
        )
        try FileManager.default.setAttributes(
            [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            ofItemAtPath: thumbDir.path
        )
    }

    // MARK: - Media (Application Support root)

    func writeStaging(fileName: String, data: Data) throws {
        let url = stagingURL(for: fileName)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func moveStagingToFinal(fileName: String) throws {
        let src = stagingURL(for: fileName)
        let dst = finalURL(for: fileName)
        try FileManager.default.moveItem(at: src, to: dst)
    }

    func removeStaging(fileName: String) throws {
        let url = stagingURL(for: fileName)
        try FileManager.default.removeItem(at: url)
    }

    func removeFinal(fileName: String) throws {
        let url = finalURL(for: fileName)
        try FileManager.default.removeItem(at: url)
    }

    func stagingExists(fileName: String) throws -> Bool {
        FileManager.default.fileExists(atPath: stagingURL(for: fileName).path)
    }

    func finalExists(fileName: String) throws -> Bool {
        FileManager.default.fileExists(atPath: finalURL(for: fileName).path)
    }

    func readFinal(fileName: String) throws -> Data {
        try Data(contentsOf: finalURL(for: fileName))
    }

    /// `Media/` 직속 파일 이름만 반환. `.staging` 서브디렉토리는 hidden(`.` prefix)으로
    /// `skipsHiddenFiles`에 의해 자연스럽게 제외된다.
    func enumerateFinal() throws -> [String] {
        let mediaURL = root.appendingPathComponent("Media", isDirectory: true)
        let urls = try FileManager.default.contentsOfDirectory(
            at: mediaURL,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        )
        return urls.map { $0.lastPathComponent }
    }

    // MARK: - Thumbnail cache (Library/Caches root, Plan C Phase 2.1)

    func writeThumb(fileName: String, data: Data) throws {
        let url = thumbURL(for: fileName)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func readThumb(fileName: String) throws -> Data {
        try Data(contentsOf: thumbURL(for: fileName))
    }

    func removeThumb(fileName: String) throws {
        let url = thumbURL(for: fileName)
        try FileManager.default.removeItem(at: url)
    }

    // MARK: - URL helpers

    private func stagingURL(for fileName: String) -> URL {
        root.appendingPathComponent("Media/.staging/\(fileName)")
    }

    private func finalURL(for fileName: String) -> URL {
        root.appendingPathComponent("Media/\(fileName)")
    }

    private func thumbURL(for fileName: String) -> URL {
        cachesRoot.appendingPathComponent("Thumbnails/\(fileName)")
    }
}
