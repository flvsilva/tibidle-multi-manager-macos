import CoreGraphics

public enum BrowserLayout {
    public static let gridGap: CGFloat = 6
    /// Share of the width (after the gaps) taken by the large pane in `.featured`.
    public static let featuredShare: CGFloat = 2.0 / 3.0

    /// Frames for panes in visual order. In single view only `selectedPosition` gets a frame;
    /// the other panes return nil and stay hidden (but loaded).
    public static func frames(count: Int, in bounds: CGRect, layout: ViewLayout, selectedPosition: Int) -> [CGRect?] {
        let g = gridGap
        switch layout {
        case .single:
            return (0..<count).map { $0 == selectedPosition ? bounds : nil }
        case .grid:
            let w = (bounds.width - g * 3) / 2
            let h = (bounds.height - g * 3) / 2
            return (0..<count).map { i in
                let column = CGFloat(i % 2), row = CGFloat(i / 2)
                // AppKit views are not flipped: row 0 is the top half.
                let y = bounds.maxY - g - h - row * (h + g)
                return CGRect(x: bounds.minX + g + column * (w + g), y: y, width: max(w, 0), height: max(h, 0))
            }
        case .featured:
            // Position 0 on the left; the others top to bottom in a column on the right.
            let mainWidth = ((bounds.width - g * 3) * featuredShare).rounded(.down)
            let sideWidth = bounds.width - g * 3 - mainWidth
            let sideCount = CGFloat(max(count - 1, 1))
            let h = (bounds.height - g * (sideCount + 1)) / sideCount
            return (0..<count).map { i in
                if i == 0 {
                    return CGRect(x: bounds.minX + g, y: bounds.minY + g, width: max(mainWidth, 0), height: max(bounds.height - g * 2, 0))
                }
                let y = bounds.maxY - g - h - CGFloat(i - 1) * (h + g)
                return CGRect(x: bounds.minX + g * 2 + mainWidth, y: y, width: max(sideWidth, 0), height: max(h, 0))
            }
        }
    }
}
