import UIKit

actor ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, UIImage>()

    private init() {
        cache.countLimit = 300
        cache.totalCostLimit = 100 * 1024 * 1024 // 100 MB
    }

    func thumbnail(for fileName: String) async -> UIImage? {
        let key = fileName as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }
        let url = await FileStorageManager.shared.getThumbnailURL(fileName: fileName)
        let image = await Task.detached(priority: .utility) {
            guard FileManager.default.fileExists(atPath: url.path) else { return nil as UIImage? }
            return UIImage(contentsOfFile: url.path)
        }.value
        if let image {
            let cost = Int(image.size.width * image.size.height * 4)
            cache.setObject(image, forKey: key, cost: cost)
        }
        return image
    }

    func invalidate(for fileName: String) {
        cache.removeObject(forKey: fileName as NSString)
    }

    func clearAll() {
        cache.removeAllObjects()
    }
}
