import AppKit

// Generate a code-native icon; no external assets or image libraries are needed.
var chunks = Data()
func bigEndian(_ value: UInt32) -> Data {
    var value = value.bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}
for (size, type) in [(128, "ic07"), (256, "ic08"), (512, "ic09"), (1024, "ic10")] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                  isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let side = CGFloat(size)
    let rect = NSRect(x: side * 0.08, y: side * 0.08, width: side * 0.84, height: side * 0.84)
    let shape = NSBezierPath(roundedRect: rect, xRadius: side * 0.19, yRadius: side * 0.19)
    NSGradient(starting: NSColor(calibratedRed: 0.23, green: 0.58, blue: 0.98, alpha: 1),
               ending: NSColor(calibratedRed: 0.10, green: 0.29, blue: 0.70, alpha: 1))!.draw(in: shape, angle: -90)
    let arrows = NSBezierPath()
    arrows.lineWidth = side * 0.055
    arrows.lineCapStyle = .round
    arrows.lineJoinStyle = .round
    arrows.move(to: NSPoint(x: side * 0.28, y: side * 0.64))
    arrows.line(to: NSPoint(x: side * 0.72, y: side * 0.64))
    arrows.move(to: NSPoint(x: side * 0.60, y: side * 0.76))
    arrows.line(to: NSPoint(x: side * 0.72, y: side * 0.64))
    arrows.line(to: NSPoint(x: side * 0.60, y: side * 0.52))
    arrows.move(to: NSPoint(x: side * 0.72, y: side * 0.36))
    arrows.line(to: NSPoint(x: side * 0.28, y: side * 0.36))
    arrows.move(to: NSPoint(x: side * 0.40, y: side * 0.48))
    arrows.line(to: NSPoint(x: side * 0.28, y: side * 0.36))
    arrows.line(to: NSPoint(x: side * 0.40, y: side * 0.24))
    NSColor.white.setStroke()
    arrows.stroke()
    NSGraphicsContext.restoreGraphicsState()
    let png = bitmap.representation(using: .png, properties: [:])!
    chunks.append(Data(type.utf8))
    chunks.append(bigEndian(UInt32(png.count + 8)))
    chunks.append(png)
}
var icon = Data("icns".utf8)
icon.append(bigEndian(UInt32(chunks.count + 8)))
icon.append(chunks)
try icon.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
