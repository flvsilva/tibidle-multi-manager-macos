// Draws the app icon (1024 × 1024 PNG). Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size = 1024.0
let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
    let inset = rect.insetBy(dx: 100, dy: 100)
    let shape = NSBezierPath(roundedRect: inset, xRadius: 185, yRadius: 185)
    NSGradient(starting: NSColor(srgbRed: 0.16, green: 0.18, blue: 0.23, alpha: 1),
               ending: NSColor(srgbRed: 0.06, green: 0.07, blue: 0.09, alpha: 1))!.draw(in: shape, angle: -90)
    NSColor(srgbRed: 0.83, green: 0.67, blue: 0.33, alpha: 1).setStroke()
    shape.lineWidth = 14
    shape.stroke()

    // 2 × 2 grid hint behind the letter.
    NSColor(srgbRed: 0.83, green: 0.67, blue: 0.33, alpha: 0.18).setFill()
    for (x, y) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
        NSBezierPath(roundedRect: NSRect(x: 215 + Double(x) * 307, y: 215 + Double(y) * 307, width: 287, height: 287),
                     xRadius: 36, yRadius: 36).fill()
    }

    let style = NSMutableParagraphStyle()
    style.alignment = .center
    let letter = NSAttributedString(string: "T", attributes: [
        .font: NSFont.systemFont(ofSize: 600, weight: .heavy),
        .foregroundColor: NSColor(srgbRed: 0.95, green: 0.80, blue: 0.44, alpha: 1),
        .paragraphStyle: style,
    ])
    let height = letter.size().height
    letter.draw(in: NSRect(x: 0, y: (size - height) / 2 - 10, width: size, height: height))
    return true
}
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
