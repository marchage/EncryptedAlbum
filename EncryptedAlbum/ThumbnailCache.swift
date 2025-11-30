import Foundation

/// Small thread-safe in-memory thumbnail cache.
/// Low-risk: keeps decrypted thumbnails in memory only and clears them on lock/when removed.
final class ThumbnailCache {
    static let shared = ThumbnailCache()

    private let cache = NSCache<NSString, NSData>()
    private let queue = DispatchQueue(label: "biz.front-end.encryptedalbum.thumbnailcache")

    private init() {
        // Limit memory usage to a reasonable amount (e.g. ~25 MB)
        cache.totalCostLimit = 25 * 1024 * 1024
    }

    /// Get a cached thumbnail for the given id
    func get(_ id: UUID) -> Data? {
        return queue.sync {
            guard let ns = cache.object(forKey: id.uuidString as NSString) else { return nil }
            return Data(ns as Data)
        }
    }

    /// Store a thumbnail data for the given id
    func set(_ data: Data, for id: UUID) {
        queue.async {
            // Use size as cost
            let cost = data.count
            self.cache.setObject(data as NSData, forKey: id.uuidString as NSString, cost: cost)
        }
    }

    /// Remove a single thumbnail from the cache
    func remove(_ id: UUID) {
        queue.async {
            self.cache.removeObject(forKey: id.uuidString as NSString)
        }
    }

    /// Clear the entire in-memory cache
    func clear() {
        queue.async {
            self.cache.removeAllObjects()
        }
    }
}
