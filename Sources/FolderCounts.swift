import Foundation

/// Counts only requested, displayed folders; directory modification time invalidates cached counts.
final class FolderCounts {
    static let shared = FolderCounts()
    private let queue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 2; q.qualityOfService = .utility; return q }()
    private let cache = NSCache<NSString, NSNumber>()
    func request(_ entry: Entry, completion: @escaping (Int?) -> Void) -> Operation? {
        // Home's protected folders can trigger access dialogs merely by showing Home.
        // Do not enumerate them for a caption; entering the folder remains an explicit action.
        let home = FileManager.default.homeDirectoryForCurrentUser
        if ["Desktop", "Documents", "Downloads", "Pictures", "Movies", "Music"].contains(entry.url.lastPathComponent),
           entry.url.deletingLastPathComponent().standardizedFileURL == home.standardizedFileURL { return nil }
        let key = Thumbnails.key(entry) as NSString
        if let cached = cache.object(forKey: key) { completion(cached.intValue); return nil }
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self, weak operation] in
            guard let self, let operation, !operation.isCancelled else { return }
            let values = try? entry.url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey])
            guard !(values?.isUbiquitousItem == true && values?.ubiquitousItemDownloadingStatus == .notDownloaded) else { return }
            let count = (try? FileManager.default.contentsOfDirectory(at: entry.url, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]))?.count
            guard !operation.isCancelled else { return }
            DispatchQueue.main.async { [weak self] in
                guard !operation.isCancelled else { return }
                if let count { self?.cache.setObject(NSNumber(value: count), forKey: key) }
                completion(count)
            }
        }
        queue.addOperation(operation); return operation
    }
}
