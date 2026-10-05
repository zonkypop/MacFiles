import AppKit
import ImageIO
import CryptoKit
import UniformTypeIdentifiers
import QuickLookThumbnailing

/// Main-thread request ownership; image decoding and disk IO stay on two workers.
final class Thumbnails {
    static let shared = Thumbnails()
    static let pixelLimit = 320 // Largest grid icon (160 points) at Retina resolution.
    private final class Cached: NSObject {
        let image: CGImage?
        let expires: Date
        init(_ image: CGImage?) { self.image = image; expires = image == nil ? Date().addingTimeInterval(60) : .distantFuture }
    }
    private final class Pending {
        let operation: BlockOperation
        var callbacks: [UUID: (CGImage?) -> Void] = [:]
        init(_ operation: BlockOperation) { self.operation = operation }
    }
    struct Ticket { let key: String; let id: UUID }
    private let memory = NSCache<NSString, Cached>()
    private let workers = OperationQueue()
    private var pending: [String: Pending] = [:]
    let directory: URL
    private let pruneLock = NSLock()
    private var writes = 0

    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("local.mintfiles.app/Thumbnails-v1", isDirectory: true)
        memory.totalCostLimit = 64 * 1024 * 1024; memory.countLimit = 512
        workers.maxConcurrentOperationCount = 2; workers.qualityOfService = .utility
        workers.name = "MintFiles thumbnails"
        workers.addOperation { [weak self] in self?.prune() }
    }
    static func canPreview(_ entry: Entry) -> Bool {
        guard !entry.directory else { return false }
        if let type = UTType(filenameExtension: entry.url.pathExtension), type.conforms(to: .image) { return true }
        return ["png", "webp", "avif", "jpg", "jpeg", "gif", "heic", "heif", "tif", "tiff", "bmp", "ico"].contains(entry.url.pathExtension.lowercased())
    }
    static func key(_ entry: Entry) -> String {
        let identity = "v1|320|\(entry.url.standardizedFileURL.path)|\(entry.size)|\(entry.modified?.timeIntervalSince1970 ?? 0)"
        return SHA256.hash(data: Data(identity.utf8)).map { String(format: "%02x", $0) }.joined()
    }
    @discardableResult
    func request(_ entry: Entry, completion: @escaping (CGImage?) -> Void) -> Ticket? {
        precondition(Thread.isMainThread)
        guard Self.canPreview(entry) else { completion(nil); return nil }
        let key = Self.key(entry), id = UUID()
        if let cached = memory.object(forKey: key as NSString), cached.expires > Date() {
            completion(cached.image); return nil
        }
        if let existing = pending[key] {
            existing.callbacks[id] = completion; return Ticket(key: key, id: id)
        }
        let operation = BlockOperation()
        let job = Pending(operation); job.callbacks[id] = completion; pending[key] = job
        operation.addExecutionBlock { [weak self, weak operation, weak job] in
            guard let self, let operation, let job, !operation.isCancelled else { return }
            let image: CGImage? = autoreleasepool {
                let cachedURL = self.directory.appendingPathComponent(key + ".png")
                if let source = CGImageSourceCreateWithURL(cachedURL as CFURL, nil),
                   let image = CGImageSourceCreateThumbnailAtIndex(source, 0, Self.options) {
                    try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: cachedURL.path)
                    return image
                }
                guard !operation.isCancelled else { return nil }
                // Do not trigger full downloads of cloud-only originals while scrolling.
                if let values = try? entry.url.resourceValues(forKeys: [.isUbiquitousItemKey, .ubiquitousItemDownloadingStatusKey]),
                   values.isUbiquitousItem == true, values.ubiquitousItemDownloadingStatus == .notDownloaded { return nil }
                let image = Self.decode(entry.url) ?? Self.quickLook(entry.url, operation: operation)
                guard !operation.isCancelled else { return nil }
                if let image {
                    try? FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                    if let data = Self.png(image) {
                        try? data.write(to: cachedURL, options: .atomic)
                        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: cachedURL.path)
                    }
                    self.pruneLock.lock(); self.writes += 1; let shouldPrune = self.writes % 32 == 0; self.pruneLock.unlock()
                    if shouldPrune { self.prune() }
                }
                return image
            }
            DispatchQueue.main.async { [weak self, weak job] in
                guard let self, let job, self.pending[key] === job else { return }
                self.pending.removeValue(forKey: key)
                guard !operation.isCancelled else { return }
                self.memory.setObject(Cached(image), forKey: key as NSString, cost: image.map { $0.bytesPerRow * $0.height } ?? 1)
                job.callbacks.values.forEach { $0(image) }
            }
        }
        workers.addOperation(operation)
        return Ticket(key: key, id: id)
    }
    func cancel(_ ticket: Ticket?) {
        precondition(Thread.isMainThread)
        guard let ticket, let job = pending[ticket.key] else { return }
        job.callbacks.removeValue(forKey: ticket.id)
        if job.callbacks.isEmpty { job.operation.cancel(); pending.removeValue(forKey: ticket.key) }
    }
    static var options: CFDictionary {
        [kCGImageSourceCreateThumbnailFromImageAlways: true,
         kCGImageSourceCreateThumbnailWithTransform: true,
         kCGImageSourceShouldCacheImmediately: true,
         kCGImageSourceThumbnailMaxPixelSize: pixelLimit] as CFDictionary
    }
    static func decode(_ url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options)
    }
    private final class ResultBox: @unchecked Sendable {
        let lock = NSLock()
        var image: CGImage?
    }
    private static func quickLook(_ url: URL, operation: Operation) -> CGImage? {
        guard !operation.isCancelled else { return nil }
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: pixelLimit, height: pixelLimit), scale: 1, representationTypes: .thumbnail)
        let semaphore = DispatchSemaphore(value: 0), box = ResultBox()
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { result, _ in
            box.lock.lock(); box.image = result?.cgImage; box.lock.unlock(); semaphore.signal()
        }
        let deadline = Date().addingTimeInterval(5)
        while semaphore.wait(timeout: .now() + 0.1) == .timedOut {
            if operation.isCancelled || Date() >= deadline { QLThumbnailGenerator.shared.cancel(request); return nil }
        }
        box.lock.lock(); defer { box.lock.unlock() }
        return box.image
    }
    static func png(_ image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }
    /// Evict oldest cached thumbnails above 256 MB. Serialized; never scans on the UI thread.
    private func prune() {
        pruneLock.lock(); defer { pruneLock.unlock() }
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]) else { return }
        let files = urls.filter { $0.pathExtension == "png" }.compactMap { url -> (URL, Int, Date)? in
            guard let value = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) else { return nil }
            return (url, value.fileSize ?? 0, value.contentModificationDate ?? .distantPast)
        }.sorted { $0.2 < $1.2 }
        var total = files.reduce(0) { $0 + $1.1 }
        for (url, size, _) in files where total > 256 * 1024 * 1024 {
            if (try? FileManager.default.removeItem(at: url)) != nil { total -= size }
        }
    }
}
