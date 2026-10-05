import AppKit

struct Entry: Equatable {
    let url: URL
    let directory: Bool
    let size: Int64
    let modified: Date?
    let kind: String
}

enum Files {
    static func entries(at url: URL, hidden: Bool) throws -> [Entry] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
        return try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys,
            options: hidden ? [] : [.skipsHiddenFiles]).map { item in
                let v = try item.resourceValues(forKeys: Set(keys))
                return Entry(url: item, directory: v.isDirectory ?? false, size: Int64(v.fileSize ?? 0),
                             modified: v.contentModificationDate, kind: v.isDirectory == true ? "Folder" : (item.pathExtension.isEmpty ? "File" : item.pathExtension.uppercased() + " file"))
            }.sorted {
                if $0.directory != $1.directory { return $0.directory }
                return $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }
    }
    static func destination(for source: URL, in folder: URL) throws -> URL {
        let target = folder.appendingPathComponent(source.lastPathComponent)
        guard source.standardizedFileURL != target.standardizedFileURL else {
            throw NSError(domain: "MintFiles", code: 1, userInfo: [NSLocalizedDescriptionKey: "Source and destination are the same."])
        }
        let realSource = source.resolvingSymlinksInPath().path
        let realFolder = folder.resolvingSymlinksInPath().path
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(atPath: source.path, isDirectory: &isDirectory), isDirectory.boolValue,
           realFolder == realSource || realFolder.hasPrefix(realSource + "/") {
            throw NSError(domain: "MintFiles", code: 2, userInfo: [NSLocalizedDescriptionKey: "A folder cannot be placed inside itself."])
        }
        guard !FileManager.default.fileExists(atPath: target.path) else {
            throw NSError(domain: "MintFiles", code: 3, userInfo: [NSLocalizedDescriptionKey: "“\(target.lastPathComponent)” already exists. No files were overwritten."])
        }
        return target
    }
    static func validName(_ name: String) -> Bool {
        !name.isEmpty && name != "." && name != ".." && !name.contains("/") && !name.contains("\0")
    }
}

final class FileTable: NSTableView {
    var activated: (() -> Void)?
    var openSelection: (() -> Void)?
    var previewSelection: (() -> Void)?
    override func mouseDown(with event: NSEvent) { activated?(); super.mouseDown(with: event) }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 49 && event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty {
            if !event.isARepeat { previewSelection?() }
        } else if event.keyCode == 36 { openSelection?() } else { super.keyDown(with: event) }
    }
    override func menu(for event: NSEvent) -> NSMenu? {
        activated?()
        let row = row(at: convert(event.locationInWindow, from: nil))
        if row >= 0 && !selectedRowIndexes.contains(row) { selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false) }
        if row < 0 { deselectAll(nil) }
        return super.menu(for: event)
    }
}

final class Pane: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate, NSCollectionViewDataSource, NSCollectionViewDelegate {
    let table = FileTable()
    let grid = FileGrid()
    let scroll = ZoomScrollView()
    let gridLayout = NSCollectionViewFlowLayout()
    let sizeSlider = NSSlider(value: 72, minValue: 32, maxValue: 160, target: nil, action: nil)
    var gridMode = UserDefaults.standard.object(forKey: "gridMode") as? Bool ?? true
    var iconSize = CGFloat(UserDefaults.standard.object(forKey: "iconSize") as? Double ?? 72)
    var selectedIndexes: IndexSet { gridMode ? grid.selectionIndexes : table.selectedRowIndexes }
    var fileView: NSView { gridMode ? grid : table }
    let path = NSTextField()
    let status = NSTextField(labelWithString: "")
    var folder: URL
    var history: [URL]
    var historyIndex = 0
    var entries: [Entry] = []
    var showHidden = false
    var filter = ""
    var changed: (() -> Void)?
    var activated: (() -> Void)?
    var error: ((Error) -> Void)?
    var dropped: (([URL], URL) -> Void)?
    var previewSelection: (() -> Void)?
    private var generation = 0
    private var loading = false
    var dragging = false
    private let dateFormatter: DateFormatter = { let f = DateFormatter(); f.dateStyle = .medium; f.timeStyle = .short; return f }()
    var selection: [URL] { selectedIndexes.compactMap { entries.indices.contains($0) ? entries[$0].url : nil } }

    init(folder: URL) { self.folder = folder; history = [folder]; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError() }
    override func loadView() {
        view = NSView()
        path.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        path.maximumNumberOfLines = 1
        (path.cell as? NSTextFieldCell)?.isScrollable = true
        path.target = self; path.action = #selector(pathEntered); path.delegate = self
        path.placeholderString = "Enter a folder path"
        scroll.hasVerticalScroller = true; scroll.hasHorizontalScroller = false
        table.usesAlternatingRowBackgroundColors = true; table.rowHeight = 28
        table.allowsMultipleSelection = true; table.style = .plain
        for (id, title, width) in [("name", "Name", 280.0), ("size", "Size", 90.0), ("kind", "Type", 130.0), ("date", "Modified", 165.0)] {
            let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier(id)); col.title = title; col.width = width
            col.minWidth = id == "name" ? 160 : 65
            col.sortDescriptorPrototype = NSSortDescriptor(key: id, ascending: true)
            table.addTableColumn(col)
        }
        table.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        table.dataSource = self; table.delegate = self; table.target = self; table.doubleAction = #selector(openSelected)
        table.activated = { [weak self] in self?.activated?() }
        table.openSelection = { [weak self] in self?.openSelected() }
        table.previewSelection = { [weak self] in self?.previewSelection?() }
        table.setDraggingSourceOperationMask(.copy, forLocal: false)
        table.setDraggingSourceOperationMask(.copy, forLocal: true)
        table.registerForDraggedTypes([.fileURL])
        grid.collectionViewLayout = gridLayout; grid.isSelectable = true; grid.allowsMultipleSelection = true
        grid.backgroundColors = [.white]; grid.dataSource = self; grid.delegate = self
        grid.register(GridItem.self, forItemWithIdentifier: NSUserInterfaceItemIdentifier("file"))
        grid.activated = { [weak self] in self?.activated?() }
        grid.openSelection = { [weak self] in self?.openSelected() }
        grid.previewSelection = { [weak self] in self?.previewSelection?() }
        grid.selectionChanged = { [weak self] in self?.updateStatus() }
        grid.setDraggingSourceOperationMask(.copy, forLocal: false)
        grid.setDraggingSourceOperationMask(.copy, forLocal: true)
        grid.registerForDraggedTypes([.fileURL])
        gridLayout.minimumInteritemSpacing = 8; gridLayout.minimumLineSpacing = 12
        gridLayout.sectionInset = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        sizeSlider.target = self; sizeSlider.action = #selector(sliderChanged)
        sizeSlider.toolTip = "Item size · Control + mouse wheel"
        sizeSlider.setAccessibilityLabel("Item size")
        scroll.zoom = { [weak self] delta in guard let self else { return }; self.setIconSize(self.iconSize + delta * 4) }
        scroll.documentView = gridMode ? grid : table
        setIconSize(iconSize, persist: false)
        status.font = .systemFont(ofSize: 11); status.textColor = .secondaryLabelColor
        for child in [scroll, status, sizeSlider] { child.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(child) }
        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: view.topAnchor), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor), scroll.bottomAnchor.constraint(equalTo: status.topAnchor, constant: -4),
            status.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10), status.trailingAnchor.constraint(lessThanOrEqualTo: sizeSlider.leadingAnchor, constant: -10), status.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -5), status.heightAnchor.constraint(equalToConstant: 20),
            sizeSlider.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12), sizeSlider.centerYAnchor.constraint(equalTo: status.centerYAnchor), sizeSlider.widthAnchor.constraint(equalToConstant: 105)
        ])
        reload()
    }
    func render(selected: Set<URL>) {
        let indexes = IndexSet(entries.indices.filter { selected.contains(entries[$0].url) })
        table.reloadData(); grid.reloadData()
        table.selectRowIndexes(indexes, byExtendingSelection: false); grid.selectionIndexes = indexes
    }
    func setMode(grid enabled: Bool) {
        let selected = Set(selection)
        gridMode = enabled; UserDefaults.standard.set(enabled, forKey: "gridMode")
        scroll.documentView = enabled ? grid : table
        scroll.hasHorizontalScroller = !enabled
        render(selected: selected); updateStatus()
        view.window?.makeFirstResponder(fileView); changed?()
    }
    @objc func sliderChanged() { setIconSize(CGFloat(sizeSlider.doubleValue)) }
    func setIconSize(_ size: CGFloat, persist: Bool = true) {
        let selected = Set(selection)
        iconSize = min(160, max(32, size)); sizeSlider.doubleValue = Double(iconSize)
        gridLayout.itemSize = NSSize(width: max(88, iconSize + 26), height: iconSize + 68)
        gridLayout.invalidateLayout()
        table.rowHeight = max(24, min(64, iconSize / 2) + 8)
        render(selected: selected)
        if persist { UserDefaults.standard.set(Double(iconSize), forKey: "iconSize") }
    }
    func selectAllFiles(_ sender: Any?) { if gridMode { grid.selectAll(sender) } else { table.selectAll(sender) } }
    func numberOfSections(in collectionView: NSCollectionView) -> Int { 1 }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { entries.count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: NSUserInterfaceItemIdentifier("file"), for: indexPath) as! GridItem
        return item
    }
    func collectionView(_ collectionView: NSCollectionView, didEndDisplaying item: NSCollectionViewItem, forRepresentedObjectAt indexPath: IndexPath) {
        (item as? GridItem)?.stopThumbnail()
    }
    func collectionView(_ collectionView: NSCollectionView, willDisplay item: NSCollectionViewItem, forRepresentedObjectAt indexPath: IndexPath) {
        if entries.indices.contains(indexPath.item) { (item as? GridItem)?.configure(entries[indexPath.item], size: iconSize) }
    }
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) { updateStatus() }
    func collectionView(_ collectionView: NSCollectionView, didDeselectItemsAt indexPaths: Set<IndexPath>) { updateStatus() }
    func collectionView(_ collectionView: NSCollectionView, pasteboardWriterForItemAt indexPath: IndexPath) -> NSPasteboardWriting? { entries[indexPath.item].url as NSURL }
    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forItemsAt indexPaths: Set<IndexPath>) { dragging = true }
    func collectionView(_ collectionView: NSCollectionView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, dragOperation operation: NSDragOperation) { dragging = false }
    func collectionView(_ collectionView: NSCollectionView, validateDrop info: NSDraggingInfo, proposedIndexPath indexPath: AutoreleasingUnsafeMutablePointer<NSIndexPath>, dropOperation: UnsafeMutablePointer<NSCollectionView.DropOperation>) -> NSDragOperation {
        let item = (indexPath.pointee as IndexPath).item
        dropOperation.pointee = entries.indices.contains(item) && entries[item].directory ? .on : .before
        return info.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : []
    }
    func collectionView(_ collectionView: NSCollectionView, acceptDrop info: NSDraggingInfo, indexPath: IndexPath, dropOperation: NSCollectionView.DropOperation) -> Bool {
        let urls = (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else { return false }
        let destination = dropOperation == .on && entries.indices.contains(indexPath.item) && entries[indexPath.item].directory ? entries[indexPath.item].url : folder
        dropped?(urls, destination); return true
    }
    func controlTextDidBeginEditing(_ obj: Notification) { activated?() }
    @objc func pathEntered() {
        let expanded = (path.stringValue as NSString).expandingTildeInPath
        let url = expanded.hasPrefix("/") ? URL(fileURLWithPath: expanded) : folder.appendingPathComponent(expanded)
        navigate(url)
    }
    func navigate(_ url: URL, record: Bool = true) {
        let candidate = url.standardizedFileURL
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: candidate.path, isDirectory: &isDir), isDir.boolValue else {
            error?(NSError(domain: "MintFiles", code: 4, userInfo: [NSLocalizedDescriptionKey: "This folder is unavailable: \(candidate.path)"])); path.stringValue = folder.path; return
        }
        folder = candidate
        entries = []; render(selected: [])
        if record {
            history = Array(history.prefix(historyIndex + 1)); history.append(candidate); historyIndex = history.count - 1
        }
        filter = ""; reload(); changed?()
    }
    func back() { guard historyIndex > 0 else { return }; historyIndex -= 1; navigate(history[historyIndex], record: false) }
    func forward() { guard historyIndex + 1 < history.count else { return }; historyIndex += 1; navigate(history[historyIndex], record: false) }
    func reload(silent: Bool = false) {
        guard isViewLoaded, !(silent && (loading || dragging)) else { return }
        loading = true
        generation += 1
        let ticket = generation, current = folder, hidden = showHidden, query = filter
        let selected = Set(selection)
        path.stringValue = folder.path
        if !silent { status.stringValue = "Loading…" }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try Files.entries(at: current, hidden: hidden).filter { query.isEmpty || $0.url.lastPathComponent.localizedCaseInsensitiveContains(query) } }
            DispatchQueue.main.async {
                guard let self, self.generation == ticket else { return }
                self.loading = false
                switch result {
                case .success(let rows):
                    let updated = self.sorted(rows)
                    if silent && updated == self.entries { return }
                    self.entries = updated; self.render(selected: selected)
                    self.updateStatus()
                case .failure(let failure):
                    self.entries = []; self.render(selected: []); self.status.stringValue = failure.localizedDescription
                }
            }
        }
    }
    func updateStatus() {
        status.stringValue = "\(entries.count) items" + (selection.isEmpty ? "" : " · \(selection.count) selected") + (showHidden ? " · hidden files shown" : "")
    }
    @objc func openSelected() {
        guard let item = selectedIndexes.first, entries.indices.contains(item) else { return }
        if entries[item].directory { navigate(entries[item].url) }
        else { NSWorkspace.shared.open(entries[item].url) }
    }
    func sorted(_ rows: [Entry]) -> [Entry] {
        let descriptor = table.sortDescriptors.first
        let key = descriptor?.key ?? "name", ascending = descriptor?.ascending ?? true
        return rows.sorted { a, b in
            if a.directory != b.directory { return a.directory }
            let comparison: ComparisonResult
            switch key {
            case "size": comparison = a.size == b.size ? a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent) : (a.size < b.size ? .orderedAscending : .orderedDescending)
            case "date": comparison = (a.modified ?? .distantPast).compare(b.modified ?? .distantPast)
            case "kind": comparison = a.kind.localizedStandardCompare(b.kind)
            default: comparison = a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent)
            }
            return ascending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }
    func tableView(_ tableView: NSTableView, sortDescriptorsDidChange oldDescriptors: [NSSortDescriptor]) {
        let selected = Set(selection); entries = sorted(entries); render(selected: selected)
    }
    func numberOfRows(in tableView: NSTableView) -> Int { entries.count }
    func tableViewSelectionDidChange(_ notification: Notification) { updateStatus() }
    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, willBeginAt screenPoint: NSPoint, forRowIndexes rowIndexes: IndexSet) { dragging = true }
    func tableView(_ tableView: NSTableView, draggingSession session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) { dragging = false }
    func tableView(_ tableView: NSTableView, pasteboardWriterForRow row: Int) -> NSPasteboardWriting? { entries[row].url as NSURL }
    func tableView(_ tableView: NSTableView, validateDrop info: NSDraggingInfo, proposedRow row: Int, proposedDropOperation operation: NSTableView.DropOperation) -> NSDragOperation {
        if operation == .on && entries.indices.contains(row) && entries[row].directory {
            tableView.setDropRow(row, dropOperation: .on)
        } else { tableView.setDropRow(-1, dropOperation: .on) }
        return info.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .copy : []
    }
    func tableView(_ tableView: NSTableView, acceptDrop info: NSDraggingInfo, row: Int, dropOperation: NSTableView.DropOperation) -> Bool {
        let urls = (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        guard !urls.isEmpty else { return false }
        let destination = entries.indices.contains(row) && entries[row].directory ? entries[row].url : folder
        activated?(); dropped?(urls, destination); return true
    }
    func tableView(_ tableView: NSTableView, didRemove rowView: NSTableRowView, forRow row: Int) {
        for cell in rowView.subviews.compactMap({ $0 as? FileNameCell }) { cell.stopThumbnail() }
    }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = entries[row], id = tableColumn?.identifier.rawValue ?? "name"
        if id == "name" {
            let identifier = NSUserInterfaceItemIdentifier("fileName")
            let cell = tableView.makeView(withIdentifier: identifier, owner: self) as? FileNameCell ?? FileNameCell()
            cell.identifier = identifier
            cell.configure(entry, size: min(64, iconSize / 2), fontSize: min(18, 11 + iconSize / 32))
            return cell
        }
        let cell = NSTableCellView()
        let label = NSTextField(labelWithString: ""); label.font = .systemFont(ofSize: min(18, 11 + iconSize / 32)); label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(label); cell.textField = label
        let leading: CGFloat = 8
        if id == "size" { label.stringValue = entry.directory ? "—" : ByteCountFormatter.string(fromByteCount: entry.size, countStyle: .file) }
        else if id == "kind" { label.stringValue = entry.kind }
        else { label.stringValue = entry.modified.map { dateFormatter.string(from: $0) } ?? "—" }
        NSLayoutConstraint.activate([label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: leading), label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6), label.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
        return cell
    }
}

final class BrowserTab {
    let pane: Pane
    init(folder: URL) { pane = Pane(folder: folder) }
}

final class Browser: NSWindowController, NSTableViewDataSource, NSTableViewDelegate, NSSearchFieldDelegate, NSWindowDelegate {
    let imagePreview = ImagePreview()
    let sidebar = NSTableView()
    let tabsControl = NSSegmentedControl()
    let search = NSSearchField()
    let content = NSView()
    let activity = NSTextField(labelWithString: "")
    let viewModes = NSSegmentedControl()
    let pathHost = NSView()
    var tabBar: NSStackView!
    var tabBarHeight: NSLayoutConstraint!
    var tabs: [BrowserTab] = []
    var currentIndex = 0
    var clipboard: [URL] = []
    var cutting = false
    var busy = false
    var refreshTimer: Timer?
    let places: [(String, URL, String)] = {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [("Home", home, "house"), ("Desktop", home.appendingPathComponent("Desktop"), "desktopcomputer"),
                ("Documents", home.appendingPathComponent("Documents"), "doc"), ("Downloads", home.appendingPathComponent("Downloads"), "arrow.down.circle"),
                ("Pictures", home.appendingPathComponent("Pictures"), "photo"), ("Music", home.appendingPathComponent("Music"), "music.note"),
                ("Applications", URL(fileURLWithPath: "/Applications"), "square.grid.2x2"), ("File System", URL(fileURLWithPath: "/"), "internaldrive"),
                ("Volumes", URL(fileURLWithPath: "/Volumes"), "externaldrive")]
    }()
    var tab: BrowserTab { tabs[currentIndex] }
    var pane: Pane { tab.pane }
    init() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1150, height: 720), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.title = "MintFiles"; window.minSize = NSSize(width: 740, height: 420)
        super.init(window: window); window.center(); window.setFrameAutosaveName("MintFilesMain")
        window.delegate = self
        setup(); newTab(nil)
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 4, repeats: true) { [weak self] _ in
            guard let self, !self.busy, self.window?.isVisible == true else { return }
            self.pane.reload(silent: true)
        }
    }
    required init?(coder: NSCoder) { fatalError() }
    func button(_ title: String, _ symbol: String, _ action: Selector) -> NSButton {
        let b = NSButton(title: title, target: self, action: action)
        b.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title); b.imagePosition = .imageOnly; b.bezelStyle = .inline
        b.isBordered = false; b.toolTip = symbol == "chevron.left" ? "Back" : symbol == "chevron.right" ? "Forward" : symbol == "arrow.up" ? "Up" : symbol == "house" ? "Home" : title
        b.widthAnchor.constraint(equalToConstant: 28).isActive = true
        return b
    }
    func setup() {
        guard let root = window?.contentView else { return }
        let toolbar = NSStackView(views: [button("Back", "chevron.left", #selector(back)), button("Forward", "chevron.right", #selector(forward)), button("Up", "arrow.up", #selector(up))])
        toolbar.spacing = 7; toolbar.addArrangedSubview(pathHost)
        pathHost.setContentHuggingPriority(.defaultLow, for: .horizontal)
        pathHost.widthAnchor.constraint(greaterThanOrEqualToConstant: 160).isActive = true
        pathHost.heightAnchor.constraint(equalToConstant: 26).isActive = true
        search.placeholderString = "Filter this folder"; search.delegate = self; search.widthAnchor.constraint(equalToConstant: 160).isActive = true
        toolbar.addArrangedSubview(search)
        viewModes.segmentCount = 2; viewModes.trackingMode = .selectOne; viewModes.target = self; viewModes.action = #selector(changeView)
        viewModes.setImage(NSImage(systemSymbolName: "square.grid.2x2.fill", accessibilityDescription: "Grid view"), forSegment: 0)
        viewModes.setImage(NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "List view"), forSegment: 1)
        viewModes.setToolTip("Grid view", forSegment: 0); viewModes.setToolTip("List view", forSegment: 1)
        toolbar.addArrangedSubview(viewModes)
        let add = button("New tab", "plus", #selector(newTab)); add.toolTip = "New tab (⌘T)"
        let close = button("Close tab", "xmark", #selector(closeTab)); close.toolTip = "Close tab (⌘W)"
        tabsControl.target = self; tabsControl.action = #selector(selectTab); tabsControl.trackingMode = .selectOne
        tabBar = NSStackView(views: [tabsControl, add, close]); tabBar.spacing = 6
        tabBarHeight = tabBar.heightAnchor.constraint(equalToConstant: 0)
        let sidebarScroll = NSScrollView(); sidebarScroll.documentView = sidebar; sidebarScroll.hasVerticalScroller = true
        let col = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("places")); col.title = "Places"; sidebar.addTableColumn(col)
        sidebar.headerView = nil; sidebar.rowHeight = 27; sidebar.style = .plain
        sidebar.backgroundColor = NSColor(calibratedWhite: 0.95, alpha: 1); sidebar.dataSource = self; sidebar.delegate = self
        sidebar.target = self; sidebar.action = #selector(placeSelected)
        let body = NSSplitView(); body.isVertical = true; body.dividerStyle = .thin
        body.addArrangedSubview(sidebarScroll); body.addArrangedSubview(content)
        sidebarScroll.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        sidebarScroll.widthAnchor.constraint(lessThanOrEqualToConstant: 190).isActive = true
        activity.font = .systemFont(ofSize: 11); activity.textColor = .secondaryLabelColor
        for child in [toolbar, tabBar!, body, activity] { child.translatesAutoresizingMaskIntoConstraints = false; root.addSubview(child) }
        NSLayoutConstraint.activate([
            toolbar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10), toolbar.topAnchor.constraint(equalTo: root.topAnchor, constant: 7), toolbar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10),
            tabBar.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10), tabBar.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10), tabBar.topAnchor.constraint(equalTo: toolbar.bottomAnchor, constant: 3), tabBarHeight,
            body.topAnchor.constraint(equalTo: tabBar.bottomAnchor, constant: 4), body.leadingAnchor.constraint(equalTo: root.leadingAnchor), body.trailingAnchor.constraint(equalTo: root.trailingAnchor), body.bottomAnchor.constraint(equalTo: activity.topAnchor, constant: -5),
            activity.leadingAnchor.constraint(equalTo: root.leadingAnchor, constant: 10), activity.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -10), activity.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -5), activity.heightAnchor.constraint(equalToConstant: 16)
        ])
        body.setPosition(170, ofDividerAt: 0)
    }
    func windowWillClose(_ notification: Notification) {
        imagePreview.dismiss(restoreFocus: false)
        refreshTimer?.invalidate()
    }
    func wire(_ t: BrowserTab) {
        for p in [t.pane] {
            p.previewSelection = { [weak self, weak p] in
                guard let self, let p, let index = p.selectedIndexes.first, p.entries.indices.contains(index),
                      Thumbnails.canPreview(p.entries[index]), let window = self.window else { return }
                self.imagePreview.navigate = { [weak p] event in
                    guard let p, !p.entries.isEmpty else { return nil }
                    if p.gridMode {
                        p.grid.keyDown(with: event)
                    } else {
                        let forward = event.keyCode == 124 || event.keyCode == 125
                        let current = p.table.selectedRowIndexes.first ?? 0
                        let next = min(p.entries.count - 1, max(0, current + (forward ? 1 : -1)))
                        p.table.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
                        p.table.scrollRowToVisible(next)
                    }
                    guard let next = p.selectedIndexes.first, p.entries.indices.contains(next) else { return nil }
                    return p.entries[next]
                }
                self.imagePreview.show(p.entries[index], parent: window, focus: p.fileView)
            }
            p.changed = { [weak self] in self?.updateTitle() }
            p.activated = { [weak self] in self?.updateTitle() }
            p.error = { [weak self] e in self?.showError(e) }
            p.dropped = { [weak self] urls, folder in self?.transfer(urls, to: folder, moving: false) }
            let menu = NSMenu()
            for (title, action) in [("Open", #selector(openSelection)), ("Copy", #selector(copyFiles)), ("Cut", #selector(cutFiles)), ("Paste", #selector(pasteFiles)), ("Rename…", #selector(rename)), ("Move to Trash", #selector(trash)), ("New Folder…", #selector(newFolder)), ("Open in Terminal", #selector(terminal))] {
                let item = NSMenuItem(title: title, action: action, keyEquivalent: ""); item.target = self; menu.addItem(item)
            }
            p.table.menu = menu; p.grid.menu = menu.copy() as? NSMenu
        }
    }
    @objc func newTab(_ sender: Any?) {
        let folder = tabs.isEmpty ? FileManager.default.homeDirectoryForCurrentUser : pane.folder
        let t = BrowserTab(folder: folder); wire(t); tabs.append(t); currentIndex = tabs.count - 1; displayTab()
    }
    @objc func closeTab(_ sender: Any?) {
        guard tabs.count > 1 else { window?.close(); return }
        tabs.remove(at: currentIndex); currentIndex = min(currentIndex, tabs.count - 1); displayTab()
    }
    @objc func selectTab() { currentIndex = tabsControl.selectedSegment; displayTab() }
    func displayTab() {
        content.subviews.forEach { $0.removeFromSuperview() }
        let v = pane.view; v.translatesAutoresizingMaskIntoConstraints = false; content.addSubview(v)
        NSLayoutConstraint.activate([v.leadingAnchor.constraint(equalTo: content.leadingAnchor), v.trailingAnchor.constraint(equalTo: content.trailingAnchor), v.topAnchor.constraint(equalTo: content.topAnchor), v.bottomAnchor.constraint(equalTo: content.bottomAnchor)])
        pathHost.subviews.forEach { $0.removeFromSuperview() }
        let path = pane.path; path.translatesAutoresizingMaskIntoConstraints = false; pathHost.addSubview(path)
        NSLayoutConstraint.activate([path.leadingAnchor.constraint(equalTo: pathHost.leadingAnchor), path.trailingAnchor.constraint(equalTo: pathHost.trailingAnchor), path.topAnchor.constraint(equalTo: pathHost.topAnchor), path.bottomAnchor.constraint(equalTo: pathHost.bottomAnchor)])
        search.stringValue = pane.filter; updateTitle(); window?.makeFirstResponder(pane.fileView)
    }
    func updateTitle() {
        search.stringValue = pane.filter
        tabsControl.segmentCount = tabs.count
        for (i, t) in tabs.enumerated() { tabsControl.setLabel(t.pane.folder.lastPathComponent.isEmpty ? "/" : t.pane.folder.lastPathComponent, forSegment: i); tabsControl.setWidth(140, forSegment: i) }
        tabsControl.selectedSegment = currentIndex
        window?.title = "\(pane.folder.lastPathComponent.isEmpty ? "/" : pane.folder.lastPathComponent) — MintFiles"
        viewModes.selectedSegment = pane.gridMode ? 0 : 1
        tabBar.isHidden = tabs.count == 1; tabBarHeight.constant = tabs.count == 1 ? 0 : 28
    }
    @objc func changeView() { pane.setMode(grid: viewModes.selectedSegment == 0) }
    @objc func gridView() { pane.setMode(grid: true) }
    @objc func listView() { pane.setMode(grid: false) }
    @objc func zoomIn() { pane.setIconSize(pane.iconSize + 8) }
    @objc func zoomOut() { pane.setIconSize(pane.iconSize - 8) }
    @objc func back() { pane.back() }
    @objc func forward() { pane.forward() }
    @objc func up() { pane.navigate(pane.folder.deletingLastPathComponent()) }
    @objc func home() { pane.navigate(FileManager.default.homeDirectoryForCurrentUser) }
    @objc func refresh() { pane.reload() }
    @objc func hiddenFiles() { pane.showHidden.toggle(); pane.reload() }
    @objc func focusPath() { window?.makeFirstResponder(pane.path); pane.path.selectText(nil) }
    @objc func openSelection() { pane.openSelected() }
    @objc func placeSelected() { let r = sidebar.selectedRow; if places.indices.contains(r) { pane.navigate(places[r].1) } }
    func controlTextDidChange(_ obj: Notification) { pane.filter = search.stringValue; pane.reload() }
    func numberOfRows(in tableView: NSTableView) -> Int { places.count }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let cell = NSTableCellView(); let icon = NSImageView(); let label = NSTextField(labelWithString: places[row].0)
        icon.image = NSImage(systemSymbolName: places[row].2, accessibilityDescription: nil); icon.contentTintColor = NSColor.labelColor
        label.font = .systemFont(ofSize: 12)
        for v in [icon, label] { v.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(v) }
        NSLayoutConstraint.activate([icon.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12), icon.centerYAnchor.constraint(equalTo: cell.centerYAnchor), icon.widthAnchor.constraint(equalToConstant: 18), icon.heightAnchor.constraint(equalToConstant: 18), label.leadingAnchor.constraint(equalTo: icon.trailingAnchor, constant: 10), label.centerYAnchor.constraint(equalTo: cell.centerYAnchor), label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -6)])
        return cell
    }
    func showError(_ error: Error) { let a = NSAlert(error: error); a.runModal() }
    func askName(title: String, value: String) -> String? {
        let alert = NSAlert(); alert.messageText = title; alert.addButton(withTitle: "Save"); alert.addButton(withTitle: "Cancel")
        let input = NSTextField(string: value); input.frame = NSRect(x: 0, y: 0, width: 320, height: 26); alert.accessoryView = input
        alert.window.initialFirstResponder = input
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        guard Files.validName(input.stringValue) else { showError(NSError(domain: "MintFiles", code: 5, userInfo: [NSLocalizedDescriptionKey: "Enter a filename without slashes."])); return nil }
        return input.stringValue
    }
    @objc func newFolder() {
        guard !busy, let name = askName(title: "New Folder", value: "Untitled Folder") else { return }
        do { try FileManager.default.createDirectory(at: pane.folder.appendingPathComponent(name), withIntermediateDirectories: false); pane.reload() } catch { showError(error) }
    }
    @objc func rename() {
        guard !busy, pane.selection.count == 1, let source = pane.selection.first,
              let name = askName(title: "Rename", value: source.lastPathComponent), name != source.lastPathComponent else { return }
        let target = source.deletingLastPathComponent().appendingPathComponent(name)
        do {
            guard !FileManager.default.fileExists(atPath: target.path) else { throw NSError(domain: "MintFiles", code: 6, userInfo: [NSLocalizedDescriptionKey: "That name already exists. Nothing was overwritten."]) }
            try FileManager.default.moveItem(at: source, to: target); pane.reload()
        } catch { showError(error) }
    }
    @objc func copyFiles() { setClipboard(cut: false) }
    @objc func cutFiles() { setClipboard(cut: true) }
    func setClipboard(cut: Bool) {
        guard !pane.selection.isEmpty else { return }; clipboard = pane.selection; cutting = cut
        NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects(clipboard.map { $0 as NSURL })
        activity.stringValue = "\(clipboard.count) items ready to \(cut ? "move" : "copy")"
    }
    @objc func pasteFiles() {
        guard !busy else { return }
        let board = (NSPasteboard.general.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let moving = cutting && board == clipboard
        transfer(board, to: pane.folder, moving: moving)
    }
    func transfer(_ sources: [URL], to folder: URL, moving: Bool) {
        guard !busy, !sources.isEmpty else { return }
        var plan: [(URL, URL)] = []
        do {
            var destinations = Set<URL>()
            for source in sources {
                let target = try Files.destination(for: source, in: folder)
                guard destinations.insert(target).inserted else { throw NSError(domain: "MintFiles", code: 7, userInfo: [NSLocalizedDescriptionKey: "Multiple source files have the same name."]) }
                plan.append((source, target))
            }
        } catch { showError(error); return }
        perform(label: moving ? "Moving" : "Copying", work: {
            for (source, target) in plan {
                if moving { try FileManager.default.moveItem(at: source, to: target) }
                else { try FileManager.default.copyItem(at: source, to: target) }
            }
        }, completion: { [weak self] in if moving { self?.cutting = false; self?.clipboard = []; NSPasteboard.general.clearContents() } })
    }
    @objc func trash() {
        let sources = pane.selection; guard !busy, !sources.isEmpty else { return }
        let alert = NSAlert(); alert.messageText = "Move \(sources.count) item\(sources.count == 1 ? "" : "s") to Trash?"
        alert.informativeText = "You can restore these items from the macOS Trash."; alert.addButton(withTitle: "Move to Trash"); alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        perform(label: "Moving to Trash", work: { for source in sources { try FileManager.default.trashItem(at: source, resultingItemURL: nil) } })
    }
    func perform(label: String, work: @escaping () throws -> Void, completion: (() -> Void)? = nil) {
        busy = true; activity.stringValue = "\(label)…"
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { try work() }
            DispatchQueue.main.async {
                guard let self else { return }; self.busy = false
                switch result {
                case .success: self.activity.stringValue = "\(label) complete"; completion?()
                case .failure(let e): self.activity.stringValue = "Operation stopped; some items may have completed"; self.showError(e)
                }
                for t in self.tabs { t.pane.reload() }
            }
        }
    }
    @objc func terminal() { NSWorkspace.shared.open([pane.folder], withApplicationAt: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: NSWorkspace.OpenConfiguration()) }
}

final class App: NSObject, NSApplicationDelegate {
    var browser: Browser?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let main = NSMenu()
        func section(_ title: String, _ items: [(String, Selector?, String, NSEvent.ModifierFlags)]) {
            let root = NSMenuItem(title: title, action: nil, keyEquivalent: ""); let menu = NSMenu(title: title)
            for (name, action, key, flags) in items { let item = NSMenuItem(title: name, action: action, keyEquivalent: key); item.keyEquivalentModifierMask = flags; menu.addItem(item) }
            root.submenu = menu; main.addItem(root)
        }
        section("MintFiles", [("About MintFiles", #selector(NSApplication.orderFrontStandardAboutPanel(_:)), "", []), ("Quit MintFiles", #selector(NSApplication.terminate(_:)), "q", .command)])
        section("File", [("New Tab", #selector(Browser.newTab(_:)), "t", .command), ("Close Tab", #selector(Browser.closeTab(_:)), "w", .command), ("New Folder…", #selector(Browser.newFolder), "n", [.command, .shift]), ("Open", #selector(Browser.openSelection), "o", .command), ("Rename…", #selector(Browser.rename), "r", .command), ("Move to Trash", #selector(Browser.trash), "\u{8}", .command)])
        section("Edit", [("Cut", #selector(NSText.cut(_:)), "x", .command), ("Copy", #selector(NSText.copy(_:)), "c", .command), ("Paste", #selector(NSText.paste(_:)), "v", .command), ("Select All", #selector(NSText.selectAll(_:)), "a", .command)])
        section("View", [("Grid View", #selector(Browser.gridView), "1", .command), ("List View", #selector(Browser.listView), "2", .command), ("Larger Items", #selector(Browser.zoomIn), "=", .command), ("Smaller Items", #selector(Browser.zoomOut), "-", .command), ("Show Hidden Files", #selector(Browser.hiddenFiles), "h", .command), ("Refresh", #selector(Browser.refresh), "\u{F708}", [])])
        section("Go", [("Back", #selector(Browser.back), "[", .command), ("Forward", #selector(Browser.forward), "]", .command), ("Up", #selector(Browser.up), "\u{F700}", .command), ("Home", #selector(Browser.home), "h", [.command, .shift]), ("Location", #selector(Browser.focusPath), "l", .command), ("Open in Terminal", #selector(Browser.terminal), "", [])])
        NSApp.mainMenu = main
        browser = Browser(); browser?.showWindow(nil); NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}

extension Browser {
    @objc func copy(_ sender: Any?) { copyFiles() }
    @objc func cut(_ sender: Any?) { cutFiles() }
    @objc func paste(_ sender: Any?) { pasteFiles() }
    override func selectAll(_ sender: Any?) { pane.selectAllFiles(sender) }
}

func selfTest() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appendingPathComponent("MintFiles-test-\(UUID().uuidString)")
    try fm.createDirectory(at: root, withIntermediateDirectories: false)
    defer { try? fm.removeItem(at: root) }
    let source = root.appendingPathComponent("source"), target = root.appendingPathComponent("target")
    try fm.createDirectory(at: source, withIntermediateDirectories: false); try fm.createDirectory(at: target, withIntermediateDirectories: false)
    let file = source.appendingPathComponent("hello.txt")
    try Data("hello".utf8).write(to: file); try Data().write(to: source.appendingPathComponent(".hidden"))
    let visible = try Files.entries(at: source, hidden: false)
    precondition(visible.count == 1)
    let all = try Files.entries(at: source, hidden: true)
    precondition(all.count == 2)
    let dest = try Files.destination(for: file, in: target); try fm.copyItem(at: file, to: dest)
    let contents = try String(contentsOf: dest, encoding: .utf8)
    precondition(contents == "hello")
    do { _ = try Files.destination(for: file, in: target); fatalError("Conflict accepted") } catch {}
    do { _ = try Files.destination(for: source, in: source); fatalError("Recursive copy accepted") } catch {}
    do { _ = try Files.destination(for: file, in: source); fatalError("Self-copy accepted") } catch {}
    precondition(!Files.validName("../oops") && !Files.validName("..") && Files.validName("A folder"))
    print("PASS: directory listing, hidden files, copy contents, conflict protection, recursive-copy protection, self-copy protection, filename validation")
}
if CommandLine.arguments.contains("--thumbnail-self-test") {
    do { try thumbnailSelfTest() } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
} else if CommandLine.arguments.contains("--self-test") {
    do { try selfTest() } catch { fputs("FAIL: \(error)\n", stderr); exit(1) }
} else {
    let app = NSApplication.shared
    let delegate = App(); app.delegate = delegate; app.run()
}
