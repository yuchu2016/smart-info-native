import AppKit
let destination = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath: destination, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let s = CGFloat(size)
    NSColor(calibratedRed: 0.94, green: 0.96, blue: 1, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.06, y: s * 0.06, width: s * 0.88, height: s * 0.88), xRadius: s * 0.20, yRadius: s * 0.20).fill()
    NSColor(calibratedRed: 0.14, green: 0.36, blue: 0.81, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: s * 0.23, y: s * 0.20, width: s * 0.54, height: s * 0.60), xRadius: s * 0.08, yRadius: s * 0.08).fill()
    NSColor.white.setFill()
    NSBezierPath(ovalIn: NSRect(x: s * 0.34, y: s * 0.43, width: s * 0.32, height: s * 0.27)).fill()
    NSColor(calibratedRed: 0.14, green: 0.36, blue: 0.81, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: s * 0.445, y: s * 0.515, width: s * 0.11, height: s * 0.10)).fill()
    NSColor(calibratedRed: 0.16, green: 0.67, blue: 0.45, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: s * 0.58, y: s * 0.14, width: s * 0.27, height: s * 0.27)).fill()
    let check = NSBezierPath()
    check.move(to: NSPoint(x: s * 0.645, y: s * 0.273))
    check.line(to: NSPoint(x: s * 0.69, y: s * 0.224))
    check.line(to: NSPoint(x: s * 0.78, y: s * 0.328))
    check.lineWidth = s * 0.026; check.lineCapStyle = .round; check.lineJoinStyle = .round
    NSColor.white.setStroke(); check.stroke()
    image.unlockFocus()
    guard let tiff = image.tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else { continue }
    var names: [String] = []
    if size <= 512 { names.append("icon_\(size)x\(size).png") }
    if size >= 32 { names.append("icon_\(size/2)x\(size/2)@2x.png") }
    for name in names { try png.write(to: URL(fileURLWithPath: destination).appendingPathComponent(name)) }
}
