import Foundation

actor StorageWarningService {
    static let shared = StorageWarningService()
    private let warningThreshold: Int64 = 500 * 1024 * 1024 // 500MB
    
    func isStorageLow() -> Bool {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let free = attrs[.systemFreeSize] as? Int64 else { return false }
        return free < warningThreshold
    }
    
    func freeSpace() -> Int64 {
        guard let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
              let free = attrs[.systemFreeSize] as? Int64 else { return 0 }
        return free
    }
    
    func formattedFreeSpace() -> String {
        ByteCountFormatter.string(fromByteCount: freeSpace(), countStyle: .file)
    }
}
