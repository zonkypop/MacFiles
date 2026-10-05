import AppKit

private final class PreviewPanel: NSPanel {
    var dismissPreview: (() -> Void)?
    var navigate: ((NSEvent) -> Void)?
    override var canBecomeKey: Bool { true }
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        if modifiers.isEmpty && (123...126).contains(event.keyCode) {
            navigate?(event)
        } else if modifiers.isEmpty && [49, 53, 12].contains(event.keyCode) {
            if !event.isARepeat { dismissPreview?() }
        } else if modifiers.isEmpty && [3, 103].contains(event.keyCode) {
            if !event.isARepeat { toggleFullScreen(nil) }
        } else { super.keyDown(with: event) }
    }
}

/// Wide resize targets inside the preview avoid relying on macOS's narrow outer border.
private final class PreviewContent: NSView {
    private let grip: CGFloat = 14
    private var dragFrame: NSRect?
    private var dragStart = NSPoint.zero
    private var dragEdges: (left: Bool, right: Bool, bottom: Bool, top: Bool) = (false, false, false, false)
    private static func diagonal(_ name: String) -> NSCursor {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "Resize preview") ?? NSImage(size: NSSize(width: 16, height: 16))
        image.size = NSSize(width: 20, height: 20)
        return NSCursor(image: image, hotSpot: NSPoint(x: 10, y: 10))
    }
    private static let descending = diagonal("arrow.up.left.and.arrow.down.right")
    private static let ascending = diagonal("arrow.up.right.and.arrow.down.left")
    private func edges(_ point: NSPoint) -> (left: Bool, right: Bool, bottom: Bool, top: Bool) {
        (point.x < grip, point.x > bounds.maxX - grip, point.y < grip, point.y > bounds.maxY - grip)
    }
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard window?.styleMask.contains(.fullScreen) != true else { return super.hitTest(point) }
        let local = convert(point, from: superview)
        let e = edges(local)
        if bounds.contains(local) && (e.left || e.right || e.bottom || e.top) { return self }
        return super.hitTest(point)
    }
    override func resetCursorRects() {
        guard window?.styleMask.contains(.fullScreen) != true else { return }
        let w = bounds.width, h = bounds.height
        addCursorRect(NSRect(x: 0, y: grip, width: grip, height: max(0, h - 2 * grip)), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: w - grip, y: grip, width: grip, height: max(0, h - 2 * grip)), cursor: .resizeLeftRight)
        addCursorRect(NSRect(x: grip, y: 0, width: max(0, w - 2 * grip), height: grip), cursor: .resizeUpDown)
        addCursorRect(NSRect(x: grip, y: h - grip, width: max(0, w - 2 * grip), height: grip), cursor: .resizeUpDown)
        for (x, y, cursor) in [(CGFloat(0), CGFloat(0), Self.ascending), (w - grip, h - grip, Self.ascending),
                                (CGFloat(0), h - grip, Self.descending), (w - grip, CGFloat(0), Self.descending)] {
            addCursorRect(NSRect(x: x, y: y, width: grip, height: grip), cursor: cursor)
        }
    }
    override func mouseDown(with event: NSEvent) {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        dragEdges = edges(convert(event.locationInWindow, from: nil))
        dragFrame = window.frame
        dragStart = window.convertPoint(toScreen: event.locationInWindow)
    }
    override func mouseDragged(with event: NSEvent) {
        guard let window, let initial = dragFrame else { return }
        let point = window.convertPoint(toScreen: event.locationInWindow)
        let dx = point.x - dragStart.x, dy = point.y - dragStart.y
        var frame = initial
        if dragEdges.left {
            frame.size.width = max(window.minSize.width, initial.width - dx)
            frame.origin.x = initial.maxX - frame.width
        } else if dragEdges.right { frame.size.width = max(window.minSize.width, initial.width + dx) }
        if dragEdges.bottom {
            frame.size.height = max(window.minSize.height, initial.height - dy)
            frame.origin.y = initial.maxY - frame.height
        } else if dragEdges.top { frame.size.height = max(window.minSize.height, initial.height + dy) }
        window.setFrame(frame, display: true)
        window.invalidateCursorRects(for: self)
    }
    override func mouseUp(with event: NSEvent) { dragFrame = nil }
}

/// A separate, keyboard-focused preview, matching nemo-preview's Space/Escape/Q dismissal.
final class ImagePreview: NSObject, NSWindowDelegate {
    private let panel = PreviewPanel(contentRect: NSRect(x: 0, y: 0, width: 850, height: 600),
                                     styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
    private let imageView = NSImageView()
    private let message = NSTextField(labelWithString: "")
    private let queue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 1; q.qualityOfService = .userInitiated; return q }()
    var navigate: ((NSEvent) -> Entry?)?
    private var generation = 0
    private weak var parent: NSWindow?
    private weak var focus: NSView?
    private var restoreOnClose = true

    override init() {
        super.init()
        panel.delegate = self
        panel.isReleasedWhenClosed = false
        panel.appearance = NSAppearance(named: .darkAqua)
        panel.minSize = NSSize(width: 300, height: 220)
        panel.collectionBehavior = [.fullScreenPrimary]
        panel.dismissPreview = { [weak self] in self?.dismiss() }
        panel.navigate = { [weak self] event in
            guard let self, let entry = self.navigate?(event) else { return }
            self.update(entry)
        }
        let content = PreviewContent()
        content.wantsLayer = true; content.layer?.backgroundColor = NSColor.black.cgColor
        panel.contentView = content
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        imageView.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        imageView.setContentHuggingPriority(.defaultLow, for: .horizontal)
        imageView.setContentHuggingPriority(.defaultLow, for: .vertical)
        message.textColor = .secondaryLabelColor; message.alignment = .center
        for view in [imageView, message] { view.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(view) }
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 16),
            imageView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -16),
            imageView.topAnchor.constraint(equalTo: content.topAnchor, constant: 16),
            imageView.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -40),
            message.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 12),
            message.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -12),
            message.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -12)
        ])
    }

    func show(_ entry: Entry, parent: NSWindow, focus: NSView) {
        self.parent = parent; self.focus = focus; restoreOnClose = true
        let screen = parent.screen ?? NSScreen.main
        let available = screen?.visibleFrame ?? parent.frame
        let size = NSSize(width: min(850, available.width - 40), height: min(600, available.height - 40))
        panel.setContentSize(size)
        panel.setFrameOrigin(NSPoint(x: max(available.minX, min(parent.frame.midX - panel.frame.width / 2, available.maxX - panel.frame.width)),
                                     y: max(available.minY, min(parent.frame.midY - panel.frame.height / 2, available.maxY - panel.frame.height))))
        parent.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(panel)
        update(entry)
    }

    private func update(_ entry: Entry) {
        generation += 1; let ticket = generation
        queue.cancelAllOperations()
        imageView.image = nil
        panel.title = entry.url.lastPathComponent
        guard Thumbnails.canPreview(entry) else {
            message.stringValue = "No image preview · Use arrow keys to continue"
            return
        }
        message.stringValue = "Loading…"
        let screen = parent?.screen ?? NSScreen.main
        let available = screen?.visibleFrame ?? panel.frame
        // Decode only enough pixels for this display; never load a huge full-resolution bitmap.
        let pixelSize = min(4096, max(1024, Int(max(available.width, available.height) * (screen?.backingScaleFactor ?? 2))))
        let operation = BlockOperation()
        operation.addExecutionBlock { [weak self, weak operation] in
            guard let operation, !operation.isCancelled else { return }
            let image = Thumbnails.decode(entry.url, maxPixelSize: pixelSize)
            guard !operation.isCancelled else { return }
            DispatchQueue.main.async { [weak self] in
                guard let self, self.generation == ticket, self.panel.isVisible else { return }
                self.imageView.image = image.map { NSImage(cgImage: $0, size: NSSize(width: $0.width, height: $0.height)) }
                self.message.stringValue = image == nil ? "Unable to preview this image." : "Space or Escape to close · F for full screen"
            }
        }
        queue.addOperation(operation)
    }

    func dismiss(restoreFocus: Bool = true) {
        restoreOnClose = restoreFocus
        panel.close()
    }
    func windowWillClose(_ notification: Notification) {
        generation += 1; queue.cancelAllOperations(); imageView.image = nil
        parent?.removeChildWindow(panel)
        if restoreOnClose, let parent, parent.isVisible {
            parent.makeKeyAndOrderFront(nil); parent.makeFirstResponder(focus)
        }
        parent = nil; focus = nil; navigate = nil
    }
}
