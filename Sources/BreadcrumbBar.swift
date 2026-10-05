import AppKit

private final class PathButton: NSButton {
    var url: URL?
    var currentFolder = false
    var symbol: String?
    override func draw(_ dirtyRect: NSRect) {
        let pressed = cell?.isHighlighted == true
        NSColor(calibratedWhite: pressed ? 0.70 : currentFolder ? 0.78 : 0.97, alpha: 1).setFill()
        bounds.fill()
        NSColor(calibratedWhite: 0.70, alpha: 1).setFill()
        NSRect(x: bounds.maxX - 1, y: 0, width: 1, height: bounds.height).fill()
        let textFont = NSFont.systemFont(ofSize: 13, weight: currentFolder ? .semibold : .regular)
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byTruncatingMiddle
        let attributes: [NSAttributedString.Key: Any] = [.font: textFont, .foregroundColor: NSColor.labelColor, .paragraphStyle: paragraph]
        let textSize = (title as NSString).size(withAttributes: attributes)
        let iconWidth: CGFloat = symbol == nil ? 0 : (title.isEmpty ? 12 : 15)
        let gap: CGFloat = symbol == nil || title.isEmpty ? 0 : 7
        let total = min(bounds.width - 16, textSize.width + iconWidth + gap)
        let x = (bounds.width - total) / 2
        if let symbol, let icon = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) {
            let configured = icon.withSymbolConfiguration(.init(pointSize: iconWidth, weight: .semibold)) ?? icon
            configured.draw(in: NSRect(x: x, y: (bounds.height - iconWidth) / 2, width: iconWidth, height: iconWidth))
        }
        if !title.isEmpty {
            (title as NSString).draw(in: NSRect(x: x + iconWidth + gap, y: (bounds.height - textSize.height) / 2, width: max(0, total - iconWidth - gap), height: textSize.height), withAttributes: attributes)
        }
    }
}
final class BreadcrumbBar: NSView {
    var navigate: ((URL) -> Void)?
    private var folder: URL?
    private var previousWidth: CGFloat = -1
    private let stack = NSStackView()
    override init(frame: NSRect) {
        super.init(frame: frame)
        stack.wantsLayer = true
        stack.layer?.borderWidth = 1; stack.layer?.borderColor = NSColor(calibratedWhite: 0.68, alpha: 1).cgColor
        stack.layer?.cornerRadius = 2; stack.layer?.masksToBounds = true
        stack.spacing = 0; stack.alignment = .centerY; stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: leadingAnchor), stack.centerYAnchor.constraint(equalTo: centerYAnchor), stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor)])
    }
    convenience init() { self.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }
    func setFolder(_ url: URL) { guard folder != url else { return }; folder = url; previousWidth = -1; needsLayout = true }
    override func layout() {
        super.layout()
        guard previousWidth != bounds.width, let folder else { return }
        previousWidth = bounds.width
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        let home = FileManager.default.homeDirectoryForCurrentUser
        var ancestors: [URL] = []; var current = folder
        while true { ancestors.insert(current, at: 0); if current.path == "/" { break }; current.deleteLastPathComponent() }
        let popup = PathButton(title: "", target: self, action: #selector(showAncestors(_:)))
        popup.isBordered = false; popup.symbol = "chevron.left"
        popup.toolTip = "Parent folders"; popup.setAccessibilityLabel("Parent folders")
        let menu = NSMenu()
        for url in ancestors {
            let item = NSMenuItem(title: url.path == "/" ? "File System" : url.lastPathComponent, action: #selector(chooseAncestor(_:)), keyEquivalent: "")
            item.target = self; item.representedObject = url; menu.addItem(item)
        }
        popup.menu = menu
        popup.widthAnchor.constraint(equalToConstant: 26).isActive = true
        popup.heightAnchor.constraint(equalToConstant: 30).isActive = true
        stack.addArrangedSubview(popup)
        var visible = ancestors
        if let start = ancestors.firstIndex(of: home) { visible = Array(ancestors[start...]) }
        func width(_ url: URL) -> CGFloat {
            let title = url.path == "/" ? "File System" : url.lastPathComponent
            let font = NSFont.systemFont(ofSize: 13, weight: url == folder ? .semibold : .regular)
            return min(180, max(65, ceil((title as NSString).size(withAttributes: [.font: font]).width) + (url == home ? 42 : 20)))
        }
        while visible.count > 1 && visible.reduce(CGFloat(26), { $0 + width($1) }) > bounds.width { visible.removeFirst() }
        for url in visible {
            let button = PathButton(title: url.path == "/" ? "File System" : url.lastPathComponent, target: self, action: #selector(choose(_:)))
            button.url = url; button.isBordered = false; button.currentFolder = url == folder
            button.font = .systemFont(ofSize: 13, weight: url == folder ? .semibold : .regular)
            if url == home { button.symbol = "house.fill" }
            button.toolTip = url.path; button.lineBreakMode = .byTruncatingMiddle
            button.widthAnchor.constraint(equalToConstant: min(width(url), max(50, bounds.width - 26))).isActive = true
            button.heightAnchor.constraint(equalToConstant: 30).isActive = true
            stack.addArrangedSubview(button)
        }
    }
    @objc private func showAncestors(_ sender: PathButton) {
        sender.menu?.popUp(positioning: nil, at: NSPoint(x: 0, y: 0), in: sender)
    }
    @objc private func choose(_ sender: PathButton) { if let url = sender.url { navigate?(url) } }
    @objc private func chooseAncestor(_ sender: NSMenuItem) { if let url = sender.representedObject as? URL { navigate?(url) } }
}
