import AppKit

final class ZoomScrollView: NSScrollView {
    var zoom: ((CGFloat) -> Void)?
    override func scrollWheel(with event: NSEvent) {
        if event.modifierFlags.contains(.control) {
            let delta = event.scrollingDeltaY
            if delta != 0 { zoom?(event.hasPreciseScrollingDeltas ? delta / 5 : delta) }
        } else { super.scrollWheel(with: event) }
    }
}

final class FileGrid: NSCollectionView {
    private var selectionAnchor: Int?
    private var keyboardFocus: Int?
    private var navigationSelection = IndexSet()
    var selectionChanged: (() -> Void)?
    var activated: (() -> Void)?
    var openSelection: (() -> Void)?
    var previewSelection: (() -> Void)?
    private func reconcileNavigation() {
        if selectionIndexes != navigationSelection {
            selectionAnchor = selectionIndexes.first
            keyboardFocus = selectionIndexes.last
            navigationSelection = selectionIndexes
        }
    }
    private func applySelection(focus: Int, extend: Bool) {
        if !extend || selectionAnchor == nil { selectionAnchor = focus }
        let anchor = selectionAnchor ?? focus
        selectionIndexes = extend ? IndexSet(integersIn: min(anchor, focus)...max(anchor, focus)) : IndexSet(integer: focus)
        keyboardFocus = focus; navigationSelection = selectionIndexes
        scrollToItems(at: [IndexPath(item: focus, section: 0)], scrollPosition: .nearestHorizontalEdge.union(.nearestVerticalEdge))
        selectionChanged?()
    }
    override func mouseDown(with event: NSEvent) {
        activated?(); reconcileNavigation()
        let clicked = indexPathForItem(at: convert(event.locationInWindow, from: nil))?.item
        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        if modifiers == .shift, let clicked {
            window?.makeFirstResponder(self)
            applySelection(focus: clicked, extend: true)
            return
        }
        super.mouseDown(with: event)
        keyboardFocus = clicked
        selectionAnchor = clicked
        navigationSelection = selectionIndexes
        if event.clickCount == 2 { openSelection?() }
    }
    private func columns(count: Int) -> Int {
        layoutSubtreeIfNeeded()
        guard let first = collectionViewLayout?.layoutAttributesForItem(at: IndexPath(item: 0, section: 0)) else { return 1 }
        for item in 1..<count {
            if let frame = collectionViewLayout?.layoutAttributesForItem(at: IndexPath(item: item, section: 0))?.frame,
               abs(frame.midY - first.frame.midY) > 1 { return item }
        }
        return max(1, count)
    }
    override func keyDown(with event: NSEvent) {
        let modifiers = event.modifierFlags.intersection([.shift, .control, .option, .command])
        if (123...126).contains(event.keyCode) && (modifiers.isEmpty || modifiers == .shift) {
            let count = numberOfItems(inSection: 0)
            guard count > 0 else { return }
            reconcileNavigation()
            let extending = modifiers.contains(.shift)
            let forward = event.keyCode == 124 || event.keyCode == 125
            let current = keyboardFocus ?? (forward ? selectionIndexes.last : selectionIndexes.first)
            let step = event.keyCode == 123 || event.keyCode == 124 ? 1 : columns(count: count)
            let next = current.map { item -> Int in
                if event.keyCode == 126 && item < step { return item }
                if event.keyCode == 125 && item / step == (count - 1) / step { return item }
                return min(count - 1, max(0, item + (forward ? step : -step)))
            } ?? 0
            if extending && selectionAnchor == nil { selectionAnchor = current ?? next }
            applySelection(focus: next, extend: extending)
        } else if event.keyCode == 49 && modifiers.isEmpty {
            if !event.isARepeat { previewSelection?() }
        } else if event.keyCode == 36 {
            openSelection?()
        } else {
            super.keyDown(with: event)
        }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        activated?()
        if let index = indexPathForItem(at: convert(event.locationInWindow, from: nil)) {
            if !selectionIndexPaths.contains(index) {
                selectionIndexPaths = [index]; selectionAnchor = index.item; keyboardFocus = index.item
            }
        } else { selectionIndexPaths = [] }
        selectionChanged?()
        return menu
    }
}

final class GridItem: NSCollectionViewItem {
    private let icon = NSImageView()
    private var thumbnailTicket: Thumbnails.Ticket?
    private var representedKey: String?
    private let name = NSTextField(labelWithString: "")
    private let detail = NSTextField(labelWithString: "")
    private var iconWidth: NSLayoutConstraint!
    private var iconHeight: NSLayoutConstraint!
    override var isSelected: Bool { didSet { updateSelection() } }
    override func loadView() {
        view = NSView(); view.wantsLayer = true; view.layer?.cornerRadius = 4
        name.alignment = .center; name.maximumNumberOfLines = 2; name.lineBreakMode = .byTruncatingMiddle
        detail.alignment = .center; detail.textColor = .secondaryLabelColor; detail.font = .systemFont(ofSize: 11)
        icon.imageScaling = .scaleProportionallyUpOrDown
        for child in [icon, name, detail] { child.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(child) }
        iconWidth = icon.widthAnchor.constraint(equalToConstant: 72); iconHeight = icon.heightAnchor.constraint(equalToConstant: 72)
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: view.topAnchor, constant: 8), icon.centerXAnchor.constraint(equalTo: view.centerXAnchor), iconWidth, iconHeight,
            name.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 7), name.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 3), name.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -3), name.heightAnchor.constraint(equalToConstant: 32),
            detail.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 1), detail.leadingAnchor.constraint(equalTo: name.leadingAnchor), detail.trailingAnchor.constraint(equalTo: name.trailingAnchor)
        ])
        updateSelection()
    }
    func configure(_ entry: Entry, size: CGFloat) {
        _ = view
        Thumbnails.shared.cancel(thumbnailTicket); thumbnailTicket = nil
        representedKey = Thumbnails.key(entry)
        icon.image = entry.directory ? MintIcons.folder : NSWorkspace.shared.icon(forFile: entry.url.path)
        if Thumbnails.canPreview(entry) {
            let key = representedKey
            thumbnailTicket = Thumbnails.shared.request(entry) { [weak self] image in
                guard let self, self.representedKey == key, let image else { return }
                self.icon.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
            }
        }
        iconWidth.constant = size; iconHeight.constant = size
        name.stringValue = entry.url.lastPathComponent; name.font = .systemFont(ofSize: size > 100 ? 14 : 12)
        detail.stringValue = entry.directory ? "Folder" : ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file)
        view.setAccessibilityElement(true); view.setAccessibilityLabel(entry.url.lastPathComponent)
        view.setAccessibilityRole(.button)
        updateSelection()
    }
    override func prepareForReuse() {
        Thumbnails.shared.cancel(thumbnailTicket); thumbnailTicket = nil; representedKey = nil
        icon.image = nil
        super.prepareForReuse()
    }
    func stopThumbnail() {
        Thumbnails.shared.cancel(thumbnailTicket); thumbnailTicket = nil; representedKey = nil
    }
    private func updateSelection() {
        view.layer?.backgroundColor = (isSelected ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.18) : NSColor.clear).cgColor
        name.textColor = .labelColor
    }
}

enum MintIcons {
    static let folder = NSImage(size: NSSize(width: 96, height: 96), flipped: false) { _ in
        NSColor(calibratedRed: 0.29, green: 0.47, blue: 0.70, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 4, y: 12, width: 88, height: 62), xRadius: 5, yRadius: 5).fill()
        NSBezierPath(roundedRect: NSRect(x: 4, y: 62, width: 37, height: 18), xRadius: 5, yRadius: 5).fill()
        NSColor(calibratedWhite: 0.88, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 8, y: 16, width: 80, height: 49), xRadius: 3, yRadius: 3).fill()
        NSColor(calibratedRed: 0.33, green: 0.58, blue: 0.88, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 4, y: 10, width: 88, height: 49), xRadius: 4, yRadius: 4).fill()
        return true
    }
}
