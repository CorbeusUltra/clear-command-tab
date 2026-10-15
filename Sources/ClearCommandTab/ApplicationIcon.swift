import AppKit

enum ApplicationIcon {
    /// Rasterize the supplied app artwork without cropping its native optical margin.
    /// This avoids drawing vector/custom NSImage representations directly in the panel.
    static func rasterize(_ image: NSImage?, pixels: Int = 320) -> CGImage? {
        guard let image else { return nil }
        var rect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
        let hints: [NSImageRep.HintKey: Any] = [.interpolation: NSImageInterpolation.high.rawValue]
        guard let source = image.cgImage(forProposedRect: &rect, context: nil, hints: hints),
              let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        return context.makeImage()
    }

    static func resolve(_ app: NSRunningApplication, pixels: Int) -> CGImage? {
        if let image = rasterize(app.icon, pixels: pixels) { return image }
        // Use the actual executable's enclosing app bundle, never an unrelated interpreter logo.
        var bundle = app.bundleURL
        if bundle == nil, var candidate = app.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent() {
            while candidate.path != "/" {
                if candidate.pathExtension == "app" { bundle = candidate; break }
                candidate.deleteLastPathComponent()
            }
        }
        return bundle.flatMap { rasterize(NSWorkspace.shared.icon(forFile: $0.path), pixels: pixels) }
    }

    static let fallback = rasterize(NSImage(named: NSImage.applicationIconName))
}
