import AppKit
import ImageIO

func thumbnailSelfTest() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("MintFiles-thumbnails-\(UUID().uuidString)")
    try fm.createDirectory(at: root, withIntermediateDirectories: true)
    defer { try? fm.removeItem(at: root) }
    guard let context = CGContext(data: nil, width: 2560, height: 1440, bitsPerComponent: 8, bytesPerRow: 0,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { fatalError("Context creation failed") }
    context.setFillColor(CGColor(red: 0.1, green: 0.6, blue: 0.9, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: 2560, height: 1440))
    context.setFillColor(CGColor(red: 1, green: 0.8, blue: 0.1, alpha: 1)); context.fill(CGRect(x: 600, y: 300, width: 1200, height: 700))
    let fullImage = context.makeImage()!
    let url = root.appendingPathComponent("large.png")
    try Thumbnails.png(fullImage)!.write(to: url)
    let entry = try Files.entries(at: root, hidden: false).first!
    let cacheURL = root.appendingPathComponent("cache"), cache = Thumbnails(directory: cacheURL)
    func awaitImage(_ service: Thumbnails, _ item: Entry) -> CGImage? {
        var finished = false, image: CGImage?
        service.request(item) { image = $0; finished = true }
        let deadline = Date().addingTimeInterval(10)
        while !finished && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        precondition(finished, "Thumbnail callback timed out")
        return image
    }
    let thumb = awaitImage(cache, entry)!
    precondition(thumb.width == 320 && thumb.height == 180, "Image must be downsampled with aspect ratio intact")
    let stored = cacheURL.appendingPathComponent(Thumbnails.key(entry) + ".png")
    precondition(fm.fileExists(atPath: stored.path), "Disk cache missing")
    precondition(awaitImage(cache, entry) === thumb, "Memory cache should reuse the decoded image")
    let changed = Entry(url: entry.url, directory: false, size: entry.size + 1, modified: Date(), kind: entry.kind)
    precondition(Thumbnails.key(changed) != Thumbnails.key(entry), "Changed source must invalidate cache")
    // A new service can read the existing cached thumbnail without decoding the original.
    try Data("invalid image".utf8).write(to: url)
    precondition(awaitImage(Thumbnails(directory: cacheURL), entry)?.width == 320, "Disk cache must survive service recreation")
    // Requests for the same source share a job; cancelled callbacks must not be invoked.
    let fresh = root.appendingPathComponent("fresh.png"); try Thumbnails.png(fullImage)!.write(to: fresh)
    let freshEntry = try Files.entries(at: root, hidden: false).first { $0.url.lastPathComponent == "fresh.png" }!
    var forbidden = false, received = 0
    let cancelTicket = cache.request(freshEntry) { _ in forbidden = true }
    cache.request(freshEntry) { if $0 != nil { received += 1 } }
    cache.cancel(cancelTicket)
    let deadline = Date().addingTimeInterval(10)
    while received == 0 && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    precondition(received == 1 && !forbidden, "Shared job/cancellation failed")
    // The input formats are decoded by the OS, not by loading full-size NSImages.
    if let dest = CGImageDestinationCreateWithURL(root.appendingPathComponent("sample.avif") as CFURL, "public.avif" as CFString, 1, nil) {
        CGImageDestinationAddImage(dest, fullImage, nil)
        precondition(CGImageDestinationFinalize(dest))
        precondition(Thumbnails.decode(root.appendingPathComponent("sample.avif"))?.width == 320)
        print("PASS: AVIF decoding")
    }
    let webp = root.appendingPathComponent("pixel.webp")
    try Data(base64Encoded: "UklGRh4AAABXRUJQVlA4TBEAAAAvAAAAAAfQ//73v/+BiOh/AAA=")!.write(to: webp)
    precondition(Thumbnails.decode(webp) != nil, "WebP decoding failed")
    print("PASS: WebP decoding")
    print("PASS: downsampling, aspect ratio, memory cache, persistent disk cache, source invalidation, shared requests and cancellation")
}
