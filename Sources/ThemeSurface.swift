import AppKit

enum FileTheme {
    private static func adaptive(_ name: String, light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: NSColor.Name(name), dynamicProvider: { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        })
    }
    // Nearly neutral charcoal; the small channel difference retains a cool tint.
    static let chrome = adaptive("FileChrome", light: .windowBackgroundColor,
        dark: NSColor(srgbRed: 0.145, green: 0.146, blue: 0.155, alpha: 1))
    static let status = adaptive("FileStatus", light: NSColor(calibratedWhite: 0.94, alpha: 1),
        dark: NSColor(srgbRed: 0.1025, green: 0.1035, blue: 0.111, alpha: 1))
    static let sidebar = adaptive("FileSidebar", light: .controlBackgroundColor,
        dark: NSColor(srgbRed: 0.160, green: 0.161, blue: 0.169, alpha: 1))
    static let canvas = adaptive("FileCanvas", light: .textBackgroundColor,
        dark: NSColor(srgbRed: 0.120, green: 0.121, blue: 0.128, alpha: 1))
    static let activePath = adaptive("FileActivePath", light: .quaternaryLabelColor,
        dark: NSColor(srgbRed: 0.225, green: 0.227, blue: 0.241, alpha: 1))
    static let selection = NSColor(srgbRed: 71.0 / 255, green: 169.0 / 255, blue: 1, alpha: 1)

}

/// Draw semantic colours under the current appearance instead of freezing a CGColor.
final class ThemeSurface: NSView {
    var fillColor: NSColor = .windowBackgroundColor { didSet { needsDisplay = true } }
    override func draw(_ dirtyRect: NSRect) {
        fillColor.setFill(); bounds.fill()
    }
    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance(); needsDisplay = true
    }
}

final class FileSelectionRow: NSTableRowView {
    override var interiorBackgroundStyle: NSView.BackgroundStyle { isSelected ? .normal : super.interiorBackgroundStyle }
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        FileTheme.selection.setFill(); bounds.fill()
    }
}
