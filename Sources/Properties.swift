import AppKit
import UniformTypeIdentifiers

private final class PropertyScan {
    private let lock = NSLock()
    private var stopped = false
    func cancel() { lock.lock(); stopped = true; lock.unlock() }
    var cancelled: Bool { lock.lock(); defer { lock.unlock() }; return stopped }
}

final class PropertiesWindow: NSWindowController, NSWindowDelegate {
    private var urls: [URL]
    private let name = NSTextField()
    private let fields = ["Type", "Contents", "Size", "Location", "Volume", "Created", "Modified", "Accessed"].reduce(into: [String: NSTextField]()) { $0[$1] = NSTextField(wrappingLabelWithString: "") }
    private var scan: PropertyScan?
    private var timer: Timer?
    var closed: (() -> Void)?
    var renamed: (() -> Void)?
    init(urls: [URL]) {
        self.urls = urls
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 510, height: 410), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = urls.count == 1 ? "\(urls[0].lastPathComponent) Properties" : "\(urls.count) Items Properties"
        super.init(window: window)
        window.delegate = self; window.isReleasedWhenClosed = false
        let stack = NSStackView(); stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false; window.contentView!.addSubview(stack)
        NSLayoutConstraint.activate([stack.leadingAnchor.constraint(equalTo: window.contentView!.leadingAnchor, constant: 20), stack.trailingAnchor.constraint(equalTo: window.contentView!.trailingAnchor, constant: -20), stack.topAnchor.constraint(equalTo: window.contentView!.topAnchor, constant: 20)])
        let icon = NSImageView(); icon.image = NSWorkspace.shared.icon(forFile: urls[0].path)
        icon.widthAnchor.constraint(equalToConstant: 48).isActive = true; icon.heightAnchor.constraint(equalToConstant: 48).isActive = true
        name.stringValue = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) selected items"
        name.isEditable = urls.count == 1 && urls[0].path != "/"; name.font = .systemFont(ofSize: 14, weight: .semibold)
        name.target = self; name.action = #selector(renameItem)
        let header = NSStackView(views: [icon, name]); header.spacing = 12
        stack.addArrangedSubview(header); header.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        for key in ["Type", "Contents", "Size", "Location", "Volume", "Created", "Modified", "Accessed"] {
            let label = NSTextField(labelWithString: key + ":"); label.textColor = .secondaryLabelColor; label.alignment = .right
            label.widthAnchor.constraint(equalToConstant: 72).isActive = true
            let value = fields[key]!; value.isSelectable = true; value.font = .systemFont(ofSize: 12)
            let row = NSStackView(views: [label, value]); row.alignment = .firstBaseline; row.spacing = 12
            stack.addArrangedSubview(row); row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        let close = NSButton(title: "Close", target: self, action: #selector(closeDialog)); close.bezelStyle = .rounded; close.keyEquivalent = "\u{1b}"
        stack.addArrangedSubview(close)
        refreshMetadata(); startScan()
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshMetadata(); if self?.scan == nil { self?.startScan() }
        }
        window.center()
    }
    required init?(coder: NSCoder) { fatalError() }
    private func refreshMetadata() {
        let fm = FileManager.default
        let attributes = urls.map { try? fm.attributesOfItem(atPath: $0.path) }
        let types = attributes.enumerated().map { index, attr -> String in
            if attr?[.type] as? FileAttributeType == .typeSymbolicLink { return "Symbolic link" }
            if attr?[.type] as? FileAttributeType == .typeDirectory { return "Folder" }
            return UTType(filenameExtension: urls[index].pathExtension)?.localizedDescription ?? "File"
        }
        fields["Type"]?.stringValue = Set(types).count == 1 ? types[0] : "Mixed types"
        let parents = Set(urls.map { $0.deletingLastPathComponent().path })
        fields["Location"]?.stringValue = parents.count == 1 ? parents.first! : "Multiple locations"
        let volumes = Set(urls.compactMap { try? $0.resourceValues(forKeys: [.volumeNameKey]).volumeName })
        fields["Volume"]?.stringValue = volumes.count == 1 ? volumes.first! : "Multiple volumes"
        let formatter = DateFormatter(); formatter.dateStyle = .medium; formatter.timeStyle = .medium
        for (label, key) in [("Created", URLResourceKey.creationDateKey), ("Modified", .contentModificationDateKey), ("Accessed", .contentAccessDateKey)] {
            let dates = urls.map { try? $0.resourceValues(forKeys: [key]).allValues[key] as? Date }
            fields[label]?.stringValue = urls.count == 1 ? dates.first.flatMap { $0 }.map { formatter.string(from: $0) } ?? "Unavailable" : "—"
        }
    }
    private func startScan() {
        let token = PropertyScan(); scan = token
        let targets = urls
        if fields["Size"]?.stringValue.isEmpty == true { fields["Size"]?.stringValue = "Calculating…"; fields["Contents"]?.stringValue = "Calculating…" }
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let fm = FileManager.default
            let roots = targets.filter { url in
                !targets.contains { parent in
                    guard parent != url, url.path.hasPrefix(parent.path == "/" ? "/" : parent.path + "/"),
                          let attr = try? fm.attributesOfItem(atPath: parent.path) else { return false }
                    return attr[.type] as? FileAttributeType == .typeDirectory
                }
            }
            var count = 0, hidden = 0, bytes: Int64 = 0, unreadable = false
            var last = Date.timeIntervalSinceReferenceDate
            func publish(_ complete: Bool) {
                let itemCount = count, hiddenCount = hidden, size = bytes, partial = unreadable
                DispatchQueue.main.async { [weak self] in
                    guard let self, !token.cancelled else { return }
                    self.fields["Contents"]?.stringValue = "\(itemCount) items" + (hiddenCount > 0 ? " (\(hiddenCount) hidden)" : "") + (partial ? " · Some contents unreadable" : "") + (complete ? "" : " · Calculating…")
                    self.fields["Size"]?.stringValue = ByteCountFormatter.string(fromByteCount: size, countStyle: .file) + " (\(size.formatted()) bytes)"
                    if complete { self.scan = nil }
                }
            }
            for root in roots {
                if token.cancelled { return }
                guard let attr = try? fm.attributesOfItem(atPath: root.path) else { unreadable = true; continue }
                if attr[.type] as? FileAttributeType != .typeDirectory {
                    count += 1; bytes += (attr[.size] as? NSNumber)?.int64Value ?? 0; continue
                }
                let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .isHiddenKey]
                guard let enumerator = fm.enumerator(at: root, includingPropertiesForKeys: keys, options: [], errorHandler: { _, _ in unreadable = true; return !token.cancelled }) else { unreadable = true; continue }
                for case let child as URL in enumerator {
                    if token.cancelled { return }
                    count += 1
                    do {
                        let values = try child.resourceValues(forKeys: Set(keys))
                        if values.isHidden == true { hidden += 1 }
                        if values.isSymbolicLink == true { enumerator.skipDescendants() }
                        if values.isDirectory != true || values.isSymbolicLink == true { bytes += Int64(values.fileSize ?? 0) }
                    } catch { unreadable = true }
                    if Date.timeIntervalSinceReferenceDate - last > 0.2 { publish(false); last = Date.timeIntervalSinceReferenceDate }
                }
            }
            publish(true)
        }
    }
    @objc private func renameItem() {
        guard urls.count == 1, Files.validName(name.stringValue) else { name.stringValue = urls.first?.lastPathComponent ?? ""; return }
        let old = urls[0], target = old.deletingLastPathComponent().appendingPathComponent(name.stringValue)
        guard target != old else { return }
        do {
            if FileManager.default.fileExists(atPath: target.path) { throw NSError(domain: "Files", code: 1, userInfo: [NSLocalizedDescriptionKey: "An item with that name already exists."]) }
            try FileManager.default.moveItem(at: old, to: target)
            urls = [target]; window?.title = "\(target.lastPathComponent) Properties"
            scan?.cancel(); scan = nil; refreshMetadata(); startScan(); renamed?()
        } catch { name.stringValue = old.lastPathComponent; NSAlert(error: error).runModal() }
    }
    @objc private func closeDialog() { window?.close() }
    func windowWillClose(_ notification: Notification) { scan?.cancel(); timer?.invalidate(); closed?() }
    deinit { scan?.cancel(); timer?.invalidate() }
}
