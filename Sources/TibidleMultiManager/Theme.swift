import AppKit

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    }
}

enum Theme {
    static let window = NSColor(hex: 0x0F1116)
    static let topBar = NSColor(hex: 0x14171E)
    static let toolBar = NSColor(hex: 0x101319)
    static let divider = NSColor(hex: 0x2D3039)
    static let mutedText = NSColor(hex: 0x9CA4B3)
    static let hintText = NSColor(hex: 0x737D8E)
    static let gold = NSColor(hex: 0xE8D39C)
    static let fieldText = NSColor(hex: 0xF0D797)
    static let fieldBackground = NSColor(hex: 0x0C0E13)
    static let fieldBorder = NSColor(hex: 0x655334)

    static let buttonBackground = NSColor(hex: 0x20242D)
    static let buttonBorder = NSColor(hex: 0x62512D)
    static let buttonHover = NSColor(hex: 0x34302A)
    static let tabBackground = NSColor(hex: 0x191D25)
    static let tabBorder = NSColor(hex: 0x343945)
    static let selectedBackground = NSColor(hex: 0x413620)
    static let selectedBorder = NSColor(hex: 0xD3AC55)

    // Account status dots (tabs and pane headers).
    static let statusHunting = NSColor(hex: 0x5CB85C)
    static let statusCity = NSColor(hex: 0xD3AC55)
    static let statusStale = NSColor(hex: 0xE8913A)
    static let statusDown = NSColor(hex: 0xE05252)
    static let statusOffline = NSColor(hex: 0x737D8E)

    /// The dot for a dashboard account status; nil before the page has said anything.
    static func statusColor(_ status: String?) -> NSColor? {
        switch status {
        case "hunting": return statusHunting
        case "city": return statusCity
        case "stale": return statusStale
        case "crashed", "replaced": return statusDown
        case "offline": return statusOffline
        default: return nil
        }
    }
}

/// Flat rounded button matching the dark/gold look of the Windows version.
class FlatButton: NSButton {
    var fill = Theme.buttonBackground { didSet { refresh() } }
    var stroke = Theme.buttonBorder { didSet { refresh() } }
    /// A small colored dot before the title (the account's status).
    var dot: NSColor? { didSet { if dot != oldValue { refresh() } } }
    var padding = NSSize(width: 14, height: 7)
    private var hovering = false { didSet { refresh() } }

    /// The label alone. NSButton's own title turns into the attributed title's text ("● Conta 1") once the dot
    /// is drawn, so building from it would add one more dot (and widen the button) on every refresh.
    private var label = ""
    override var title: String {
        get { label }
        set { label = newValue; super.title = newValue; refresh() }
    }
    override var isEnabled: Bool { didSet { refresh() } }

    convenience init(title: String, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        self.title = title
        self.target = target
        self.action = action
        isBordered = false
        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.borderWidth = 1
        focusRingType = .none
        setButtonType(.momentaryChange)
        refresh()
    }

    override var intrinsicContentSize: NSSize {
        let size = attributedTitle.size()
        return NSSize(width: ceil(size.width) + padding.width * 2, height: ceil(size.height) + padding.height * 2)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }

    func refresh() {
        layer?.backgroundColor = (hovering && isEnabled ? Theme.buttonHover : fill).cgColor
        layer?.borderColor = stroke.cgColor
        alphaValue = isEnabled ? 1 : 0.45
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let text = NSMutableAttributedString()
        if let dot {
            text.append(NSAttributedString(string: "● ", attributes: [.foregroundColor: dot, .font: NSFont.systemFont(ofSize: 10), .paragraphStyle: style]))
        }
        text.append(NSAttributedString(string: title, attributes: [
            .foregroundColor: Theme.gold, .font: NSFont.systemFont(ofSize: 13), .paragraphStyle: style,
        ]))
        attributedTitle = text
        invalidateIntrinsicContentSize()
    }
}

/// Account tab: a click selects it, a drag onto another tab reorders.
final class TabButton: FlatButton {
    var onDrop: ((TabButton) -> Void)?
    weak var siblings: NSView?

    override func mouseDown(with event: NSEvent) {
        guard let window else { return }
        let start = event.locationInWindow
        var dragging = false
        var target: TabButton?
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let point = next.locationInWindow
            if next.type == .leftMouseUp { break }
            if !dragging, hypot(point.x - start.x, point.y - start.y) < 4 { continue }
            if !dragging { dragging = true; alphaValue = 0.65; NSCursor.closedHand.push() }
            target?.alphaValue = 1
            target = tab(at: point)
            if target === self { target = nil }
            target?.alphaValue = 0.65
        }
        if dragging {
            NSCursor.pop()
            alphaValue = 1
            target?.alphaValue = 1
            if let target { onDrop?(target) }
        } else {
            sendAction(action, to: self.target)
        }
    }

    private func tab(at windowPoint: NSPoint) -> TabButton? {
        siblings?.subviews.compactMap { $0 as? TabButton }.first {
            $0.bounds.contains($0.convert(windowPoint, from: nil))
        }
    }
}
