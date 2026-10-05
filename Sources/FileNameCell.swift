import AppKit

/// Reusable list name cell; requests share the grid's memory/disk thumbnail cache.
final class FileNameCell: NSTableCellView {
    private let icon = NSImageView()
    private let label = NSTextField(labelWithString: "")
    private var entry: Entry?
    private var representedKey: String?
    private var ticket: Thumbnails.Ticket?
    private var iconWidth: NSLayoutConstraint!
    private var iconHeight: NSLayoutConstraint!

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        textField = label; imageView = icon
        label.lineBreakMode = .byTruncatingMiddle
        icon.imageScaling = .scaleProportionallyUpOrDown
        for view in [icon, label] { view.translatesAutoresizingMaskIntoConstraints = false; addSubview(view) }
        iconWidth = icon.widthAnchor.constraint(equalToConstant: 24)
        iconHeight = icon.heightAnchor.constraint(equalToConstant: 24)
        NSLayoutConstraint.activate([
            icon.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            icon.centerYAnchor.constraint(equalTo: centerYAnchor), iconWidth, iconHeight,
            label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 8),
            label.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            label.centerYAnchor.constraint(equalTo: centerYAnchor)
        ])
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }

    func configure(_ entry: Entry, size: CGFloat, fontSize: CGFloat) {
        stopThumbnail()
        self.entry = entry
        label.stringValue = entry.url.lastPathComponent
        label.font = .systemFont(ofSize: fontSize)
        iconWidth.constant = size; iconHeight.constant = size
        icon.image = entry.directory ? MintIcons.folder : NSWorkspace.shared.icon(forFile: entry.url.path)
        if window != nil { startThumbnail() }
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { stopThumbnail() } else { startThumbnail() }
    }
    private func startThumbnail() {
        guard let entry, Thumbnails.canPreview(entry) else { return }
        stopThumbnail()
        let key = Thumbnails.key(entry); representedKey = key
        ticket = Thumbnails.shared.request(entry) { [weak self] image in
            guard let self, self.representedKey == key, let image else { return }
            self.icon.image = NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
        }
    }
    func stopThumbnail() {
        Thumbnails.shared.cancel(ticket); ticket = nil; representedKey = nil
    }
}
