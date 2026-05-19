import Foundation

/// `FileOps`의 production 구현. Application Support 하위에 `Media/` + `Media/.staging/`
/// + `Thumbnails/` 디렉토리를 만들고, ADR #12에 따라 `isExcludedFromBackup` +
/// Data Protection (`completeUntilFirstUserAuthentication`)을 적용한다.
///
/// v1.2 C5: `init(root:) throws` — bootstrap 에러를 swallow하지 않는다 (silent
/// 부분 부트스트랩 상태로 동작하면 capture-save가 mv fail로 끝없이 재시도하는
/// failure mode가 가능).
///
/// v1.3 C3 + v1.4 C2: 단일 canonical bootstrap (중복 sample 제거).
struct MediaFileSystem: FileOps {
    let root: URL

    init(root: URL) throws {
        self.root = root
        try Self.bootstrap(root: root)
    }

    /// `Media` / `Media/.staging` / `Thumbnails` 디렉토리를 생성하고 각각에
    /// `isExcludedFromBackup` + Data Protection 속성을 설정한다.
    static func bootstrap(root: URL) throws {
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
    }

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

    private func stagingURL(for fileName: String) -> URL {
        root.appendingPathComponent("Media/.staging/\(fileName)")
    }

    private func finalURL(for fileName: String) -> URL {
        root.appendingPathComponent("Media/\(fileName)")
    }
}
