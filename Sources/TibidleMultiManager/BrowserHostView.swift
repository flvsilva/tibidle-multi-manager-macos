import AppKit
import TibidleCore

/// One account cell: a header (grid view only) above the page.
final class PaneView: NSView {
    let header: FlatButton
    let content = NSView()
    var showsHeader = false { didSet { header.isHidden = !showsHeader; needsLayout = true } }

    init(header: FlatButton) {
        self.header = header
        super.init(frame: .zero)
        header.padding = NSSize(width: 8, height: 3)
        addSubview(header)
        addSubview(content)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        let headerHeight: CGFloat = showsHeader ? header.intrinsicContentSize.height : 0
        header.frame = NSRect(x: 0, y: bounds.height - headerHeight, width: bounds.width, height: headerHeight)
        content.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bounds.height - headerHeight - (showsHeader ? 2 : 0))
        content.subviews.forEach { $0.frame = content.bounds }
    }
}

/// Places panes as a single view or a 2 × 2 grid. Panes are never removed from the
/// hierarchy, so switching views or reordering never reloads a page.
final class BrowserHostView: NSView {
    var panes: [PaneView] = [] { didSet { panes.forEach { if $0.superview !== self { addSubview($0) } }; needsLayout = true } }
    var grid = false { didSet { needsLayout = true } }
    var selectedPosition = 0 { didSet { needsLayout = true } }

    override func layout() {
        super.layout()
        let frames = BrowserLayout.frames(count: panes.count, in: bounds, grid: grid, selectedPosition: selectedPosition)
        for (pane, frame) in zip(panes, frames) {
            pane.showsHeader = grid
            pane.isHidden = frame == nil
            if let frame { pane.frame = frame }
        }
    }
}
