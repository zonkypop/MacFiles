import AppKit

final class PlacesTable: NSTableView {
    var contextMenu: ((Int) -> NSMenu?)?
    var middleClick: ((Int) -> Void)?
    override func menu(for event: NSEvent) -> NSMenu? {
        contextMenu?(row(at: convert(event.locationInWindow, from: nil)))
    }
    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 { middleClick?(row(at: convert(event.locationInWindow, from: nil))) }
        else { super.otherMouseDown(with: event) }
    }
}

private final class FolderTabButton: NSButton {
    var closeTab: (() -> Void)?
    var reorder: ((NSEvent) -> Void)?
    override func otherMouseDown(with event: NSEvent) {
        if event.buttonNumber == 2 { closeTab?() } else { super.otherMouseDown(with: event) }
    }
    override func mouseDown(with event: NSEvent) {
        // Track dragging ourselves; NSButton's tracking loop otherwise consumes drag events.
        guard let window else { return }
        var dragged = false
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseDragged {
                if hypot(next.locationInWindow.x - event.locationInWindow.x, next.locationInWindow.y - event.locationInWindow.y) > 6 { dragged = true }
            } else {
                if dragged { reorder?(next) } else { performClick(nil) }
                break
            }
        }
    }
}

private final class FolderTabSurface: NSView {
    var selected = false
    var showsSeparator = false
    var roundsLeft = false
    var roundsRight = false
    override func viewDidChangeEffectiveAppearance() { super.viewDidChangeEffectiveAppearance(); needsDisplay = true }
    override func draw(_ dirtyRect: NSRect) {
        let r: CGFloat = 8
        let left = roundsLeft ? r : 0
        let right = roundsRight ? r : 0
        let shape = NSBezierPath()
        shape.move(to: NSPoint(x: bounds.minX + left, y: bounds.minY))
        shape.line(to: NSPoint(x: bounds.maxX - right, y: bounds.minY))
        shape.appendArc(withCenter: NSPoint(x: bounds.maxX - right, y: bounds.minY + right), radius: right, startAngle: 270, endAngle: 360)
        shape.line(to: NSPoint(x: bounds.maxX, y: bounds.maxY - right))
        shape.appendArc(withCenter: NSPoint(x: bounds.maxX - right, y: bounds.maxY - right), radius: right, startAngle: 0, endAngle: 90)
        shape.line(to: NSPoint(x: bounds.minX + left, y: bounds.maxY))
        shape.appendArc(withCenter: NSPoint(x: bounds.minX + left, y: bounds.maxY - left), radius: left, startAngle: 90, endAngle: 180)
        shape.line(to: NSPoint(x: bounds.minX, y: bounds.minY + left))
        shape.appendArc(withCenter: NSPoint(x: bounds.minX + left, y: bounds.minY + left), radius: left, startAngle: 180, endAngle: 270)
        shape.close()
        (selected ? FileTheme.activeTab : FileTheme.chrome).setFill(); shape.fill()
        if showsSeparator {
            NSColor.labelColor.withAlphaComponent(0.10).setFill()
            NSRect(x: bounds.maxX - 1, y: bounds.minY, width: 1, height: bounds.height).fill()
        }
    }
}

final class FolderTabBar: NSView {
    var select: ((Int) -> Void)?
    var close: ((Int) -> Void)?
    var move: ((Int, Int) -> Void)?
    private let scroll = NSScrollView()
    private let stack = NSStackView()
    private var folders: [URL] = []
    private var selected = -1
    override init(frame: NSRect) {
        super.init(frame: frame)
        scroll.drawsBackground = false; scroll.hasHorizontalScroller = true; scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay; scroll.documentView = stack
        stack.orientation = .horizontal; stack.spacing = 0; stack.alignment = .centerY
        scroll.translatesAutoresizingMaskIntoConstraints = false; stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scroll)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor), scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor), scroll.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor), stack.topAnchor.constraint(equalTo: scroll.contentView.topAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.contentView.heightAnchor)
        ])
        setContentHuggingPriority(.defaultLow, for: .horizontal)
    }
    required init?(coder: NSCoder) { fatalError() }
    func update(folders: [URL], selected: Int) {
        guard self.folders != folders || self.selected != selected else { return }
        self.folders = folders; self.selected = selected
        stack.arrangedSubviews.forEach { stack.removeArrangedSubview($0); $0.removeFromSuperview() }
        for (index, folder) in folders.enumerated() {
            let surface = FolderTabSurface(); surface.selected = index == selected; surface.showsSeparator = index < folders.count - 1
            surface.roundsLeft = index == 0; surface.roundsRight = index == folders.count - 1
            let button = FolderTabButton(title: folder.lastPathComponent.isEmpty ? "/" : folder.lastPathComponent, target: self, action: #selector(choose(_:)))
            button.tag = index; button.isBordered = false; button.alignment = .left
            button.font = .systemFont(ofSize: 12, weight: index == selected ? .semibold : .regular)
            button.lineBreakMode = .byTruncatingTail; button.toolTip = folder.path
            button.setAccessibilityLabel(button.title + (index == selected ? ", selected tab" : ", tab"))
            button.closeTab = { [weak self] in self?.close?(index) }
            button.reorder = { [weak self] event in
                guard let self else { return }
                let point = self.stack.convert(event.locationInWindow, from: nil)
                let destination = min(folders.count - 1, max(0, Int(point.x / 180)))
                if destination != index { self.move?(index, destination) }
            }
            let closeButton = ToolbarButton(title: "Close tab", target: self, action: #selector(closeClicked(_:)))
            closeButton.tag = index; closeButton.isBordered = false
            closeButton.image = NSImage(size: NSSize(width: 12, height: 12), flipped: false) { _ in
                let cross = NSBezierPath()
                cross.move(to: NSPoint(x: 3, y: 3)); cross.line(to: NSPoint(x: 9, y: 9))
                cross.move(to: NSPoint(x: 3, y: 9)); cross.line(to: NSPoint(x: 9, y: 3))
                cross.lineWidth = 1.5; cross.lineCapStyle = .round
                NSColor.labelColor.setStroke(); cross.stroke(); return true
            }
            closeButton.image?.isTemplate = true
            closeButton.setAccessibilityLabel("Close tab")
            closeButton.imagePosition = .imageOnly; closeButton.toolTip = "Close \(button.title)"
            for child in [button, closeButton] { child.translatesAutoresizingMaskIntoConstraints = false; surface.addSubview(child) }
            NSLayoutConstraint.activate([
                surface.widthAnchor.constraint(equalToConstant: 180), surface.heightAnchor.constraint(equalToConstant: 32),
                button.leadingAnchor.constraint(equalTo: surface.leadingAnchor, constant: 10), button.trailingAnchor.constraint(equalTo: closeButton.leadingAnchor, constant: -4),
                button.topAnchor.constraint(equalTo: surface.topAnchor), button.bottomAnchor.constraint(equalTo: surface.bottomAnchor),
                closeButton.trailingAnchor.constraint(equalTo: surface.trailingAnchor, constant: -5), closeButton.centerYAnchor.constraint(equalTo: surface.centerYAnchor),
                closeButton.widthAnchor.constraint(equalToConstant: 20), closeButton.heightAnchor.constraint(equalToConstant: 20)
            ])
            stack.addArrangedSubview(surface)
        }
        layoutSubtreeIfNeeded()
        if stack.arrangedSubviews.indices.contains(selected) { stack.scrollToVisible(stack.arrangedSubviews[selected].frame) }
    }
    @objc private func choose(_ sender: NSButton) { select?(sender.tag) }
    @objc private func closeClicked(_ sender: NSButton) { close?(sender.tag) }
}
