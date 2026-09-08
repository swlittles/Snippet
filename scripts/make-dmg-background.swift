import AppKit

// Draw in points, with matching 1x/2x representations for Retina Finder windows.
let output = CommandLine.arguments[1]
let preview = CommandLine.arguments.contains("--preview")
let width = 680, height = 440
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor {
    NSColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: 1)
}
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect {
    NSRect(x: x, y: CGFloat(height) - y - h, width: w, height: h)
}
func text(_ string: String, y: CGFloat, size: CGFloat, weight: NSFont.Weight, ink: NSColor) {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    (string as NSString).draw(in: rect(24, y, 632, 48), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: ink, .paragraphStyle: style
    ])
}
for scale in [1, 2] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width * scale, pixelsHigh: height * scale,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    bitmap.size = NSSize(width: width, height: height)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    NSGradient(starting: color(250, 249, 255), ending: color(234, 229, 248))!.draw(in: rect(0, 0, 680, 440), angle: -90)
    color(25, 22, 36).setFill()
    rect(0, 0, 680, 144).fill()
    text("S N I P P E T", y: 30, size: 12, weight: .semibold, ink: color(185, 167, 249))
    text("A little shortcut. A lot less work.", y: 57, size: 27, weight: .semibold, ink: .white)
    text("Your clipboard, snippets, and calculations. One hotkey away.", y: 101, size: 13, weight: .regular, ink: color(177, 171, 192))
    // The actual draggable Finder icons sit above these subtle circular wells.
    for x: CGFloat in [138, 438] {
        color(255, 255, 255).withAlphaComponent(0.65).setFill()
        NSBezierPath(ovalIn: rect(x, 174, 104, 104)).fill()
    }
    color(143, 124, 193).setStroke()
    let arrow = NSBezierPath()
    arrow.lineWidth = 2.5
    arrow.lineCapStyle = .round
    arrow.lineJoinStyle = .round
    arrow.move(to: NSPoint(x: 311, y: 214))
    arrow.line(to: NSPoint(x: 369, y: 214))
    arrow.move(to: NSPoint(x: 359, y: 224))
    arrow.line(to: NSPoint(x: 369, y: 214))
    arrow.line(to: NSPoint(x: 359, y: 204))
    arrow.stroke()
    text("Drag Snippet to Applications", y: 337, size: 18, weight: .semibold, ink: color(42, 33, 64))
    text(preview ? "Developer preview · Not notarized" : "Then open Snippet from Applications to get started.",
         y: 367, size: 12, weight: .regular, ink: color(113, 103, 135))
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(output)/background\(scale == 2 ? "@2x" : "").png"))
}
