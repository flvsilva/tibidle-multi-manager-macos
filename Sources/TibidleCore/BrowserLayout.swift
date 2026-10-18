import CoreGraphics

public enum BrowserLayout {
    public static let gridGap: CGFloat = 6

    /// Frames for panes in visual order. In single view only `selectedPosition` gets a frame;
    /// the other panes return nil and stay hidden (but loaded).
    public static func frames(count: Int, in bounds: CGRect, grid: Bool, selectedPosition: Int) -> [CGRect?] {
        guard grid else {
            return (0..<count).map { $0 == selectedPosition ? bounds : nil }
        }
        let g = gridGap
        let w = (bounds.width - g * 3) / 2
        let h = (bounds.height - g * 3) / 2
        return (0..<count).map { i in
            let column = CGFloat(i % 2), row = CGFloat(i / 2)
            // AppKit views are not flipped: row 0 is the top half.
            let y = bounds.maxY - g - h - row * (h + g)
            return CGRect(x: bounds.minX + g + column * (w + g), y: y, width: max(w, 0), height: max(h, 0))
        }
    }
}
