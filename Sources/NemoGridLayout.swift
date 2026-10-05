import AppKit

struct GridGeometry {
    static let font = NSFont.systemFont(ofSize: 13)
    static func nameHeight(_ name: String, width: CGFloat) -> CGFloat {
        let paragraph = NSMutableParagraphStyle(); paragraph.lineBreakMode = .byWordWrapping; paragraph.alignment = .center
        let rect = (name as NSString).boundingRect(with: NSSize(width: width, height: 1000),
            options: [.usesLineFragmentOrigin, .usesFontLeading], attributes: [.font: font, .paragraphStyle: paragraph])
        return min(48, max(16, ceil(rect.height / 16) * 16))
    }
    static func imageSize(_ entry: Entry, size: CGFloat) -> CGFloat { Thumbnails.canPreview(entry) ? size * 1.2 : size }
}

/// Fixed column pitch and row heights derived from their captions, rather than stretched gaps.
final class NemoGridLayout: NSCollectionViewLayout {
    var entries: (() -> [Entry])?
    var iconSize: CGFloat = 80
    private var attributes: [NSCollectionViewLayoutAttributes] = []
    private var zones: [CGFloat] = []
    private var contentSize = NSSize.zero
    func iconZone(at index: Int) -> CGFloat { zones.indices.contains(index) ? zones[index] : iconSize * 1.2 }
    override func prepare() {
        super.prepare()
        guard let collectionView else { return }
        let rows = entries?() ?? []
        let available = collectionView.enclosingScrollView?.contentSize.width ?? collectionView.bounds.width
        let cellWidth = max(104, ceil(iconSize * 1.2 + 8)), gap: CGFloat = 6
        let columns = max(1, Int((available - 16 + gap) / (cellWidth + gap)))
        attributes = []; zones = []; var y: CGFloat = 8
        for start in stride(from: 0, to: rows.count, by: columns) {
            let end = min(rows.count, start + columns)
            let zone = rows[start..<end].map { GridGeometry.imageSize($0, size: iconSize) }.max() ?? iconSize
            let caption = rows[start..<end].map { GridGeometry.nameHeight($0.url.lastPathComponent, width: cellWidth - 6) }.max() ?? 16
            let height = zone + 6 + caption + 16 + 10
            for index in start..<end {
                let attr = NSCollectionViewLayoutAttributes(forItemWith: IndexPath(item: index, section: 0))
                attr.frame = NSRect(x: 8 + CGFloat(index - start) * (cellWidth + gap), y: y, width: cellWidth, height: height)
                attributes.append(attr); zones.append(zone)
            }
            y += height
        }
        contentSize = NSSize(width: available, height: max(y + 8, collectionView.enclosingScrollView?.contentSize.height ?? 0))
    }
    override var collectionViewContentSize: NSSize { contentSize }
    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] { attributes.filter { $0.frame.intersects(rect) } }
    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? { attributes.indices.contains(indexPath.item) ? attributes[indexPath.item] : nil }
    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool { newBounds.width != collectionView?.bounds.width }
}
