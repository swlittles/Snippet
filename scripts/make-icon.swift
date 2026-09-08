import AppKit
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let fm = FileManager.default
try fm.createDirectory(at: output, withIntermediateDirectories: true)
func rect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ radius: CGFloat, _ color: NSColor) {
    color.setFill()
    NSBezierPath(roundedRect: NSRect(x: x, y: 1024-y-h, width: w, height: h), xRadius: radius, yRadius: radius).fill()
}
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: 1) }
let logo = NSImage(size: NSSize(width: 1024, height: 1024))
logo.lockFocus()
rect(64,64,896,896,196,color(23,20,33))
rect(360,144,496,576,96,color(119,102,159))
rect(200,288,496,576,96,color(180,164,255))
for (y,w): (CGFloat,CGFloat) in [(480,256),(588,192),(696,128)] { rect(320,y,w,44,22,color(33,26,57)) }
logo.unlockFocus()
func png(_ image: NSImage, size: Int, url: URL) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    context.imageInterpolation = .high
    image.draw(in: NSRect(x: 0, y: 0, width: size, height: size), from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: url)
}
try png(logo, size: 1024, url: output.appendingPathComponent("logo-1024.png"))
let iconset = output.appendingPathComponent("Snippet.iconset")
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16,32,128,256,512] {
    try png(logo, size: size, url: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try png(logo, size: size*2, url: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let menu = NSImage(size: NSSize(width: 1024, height: 1024))
menu.lockFocus()
NSColor.black.setStroke()
let back = NSBezierPath(roundedRect: NSRect(x: 350, y: 1024-110-600, width: 540, height: 600), xRadius: 85, yRadius: 85)
back.lineWidth = 62; back.stroke()
rect(130,310,540,600,85,.black)
NSGraphicsContext.current?.cgContext.setBlendMode(.clear)
for y: CGFloat in [460,610,760] { rect(240,y,310,50,25,.white) }
NSGraphicsContext.current?.cgContext.setBlendMode(.normal)
menu.unlockFocus()
try png(menu, size: 36, url: output.appendingPathComponent("MenuIcon.png"))
