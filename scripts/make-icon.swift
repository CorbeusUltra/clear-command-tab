import AppKit

// The production icon and dark proposals share the original vector geometry.
// Default: swift scripts/make-icon.swift /path/to/ClearCommandTab.icns
// Dark resource: swift scripts/make-icon.swift --dark /path/to/ClearCommandTab-dark.icns
// Selected PNGs: swift scripts/make-icon.swift --selected-assets Design/SelectedLogo
// Earlier proposals: swift scripts/make-icon.swift --proposals Design/DarkLogoProposals
struct IconPalette {
    let id: String
    let name: String
    let start: NSColor
    let end: NSColor
    var arrowColor: NSColor = .white

    static let original = IconPalette(id: "original", name: "Original · référence",
        start: NSColor(calibratedRed: 0.23, green: 0.58, blue: 0.98, alpha: 1),
        end: NSColor(calibratedRed: 0.10, green: 0.29, blue: 0.70, alpha: 1))
    // Slightly brighter than the earlier navy proposal so black arrows retain contrast.
    static let dark = IconPalette(id: "deep-blue-black", name: "Bleu profond · flèches noires",
        start: NSColor(calibratedRed: 0.22, green: 0.49, blue: 0.79, alpha: 1),
        end: NSColor(calibratedRed: 0.12, green: 0.31, blue: 0.59, alpha: 1), arrowColor: .black)
    static let darkProposals = [
        IconPalette(id: "midnight", name: "1. Nuit",
            start: NSColor(calibratedRed: 0.14, green: 0.23, blue: 0.39, alpha: 1),
            end: NSColor(calibratedRed: 0.035, green: 0.065, blue: 0.14, alpha: 1)),
        IconPalette(id: "graphite", name: "2. Graphite",
            start: NSColor(calibratedRed: 0.29, green: 0.31, blue: 0.35, alpha: 1),
            end: NSColor(calibratedRed: 0.10, green: 0.11, blue: 0.14, alpha: 1)),
        IconPalette(id: "deep-blue", name: "3. Bleu profond",
            start: NSColor(calibratedRed: 0.14, green: 0.37, blue: 0.68, alpha: 1),
            end: NSColor(calibratedRed: 0.035, green: 0.13, blue: 0.32, alpha: 1)),
    ]
}

func drawIcon(side: CGFloat, palette: IconPalette) {
    let rect = NSRect(x: side * 0.08, y: side * 0.08, width: side * 0.84, height: side * 0.84)
    let shape = NSBezierPath(roundedRect: rect, xRadius: side * 0.19, yRadius: side * 0.19)
    NSGradient(starting: palette.start, ending: palette.end)!.draw(in: shape, angle: -90)
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
    palette.arrowColor.setStroke()
    arrows.stroke()
}

func png(width: Int, height: Int, draw: () -> Void) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)!
    draw()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

func bigEndian(_ value: UInt32) -> Data {
    var value = value.bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}

func makeProductionIcon(at url: URL, palette: IconPalette = .original) throws {
    var chunks = Data()
    for (size, type) in [(128, "ic07"), (256, "ic08"), (512, "ic09"), (1024, "ic10")] {
        let image = png(width: size, height: size) { drawIcon(side: CGFloat(size), palette: palette) }
        chunks.append(Data(type.utf8))
        chunks.append(bigEndian(UInt32(image.count + 8)))
        chunks.append(image)
    }
    var icon = Data("icns".utf8)
    icon.append(bigEndian(UInt32(chunks.count + 8)))
    icon.append(chunks)
    try icon.write(to: url)
}

func drawPreview(_ palette: IconPalette, rect: NSRect) {
    NSGraphicsContext.saveGraphicsState()
    let transform = NSAffineTransform()
    transform.translateX(by: rect.minX, yBy: rect.minY)
    transform.concat()
    drawIcon(side: rect.width, palette: palette)
    NSGraphicsContext.restoreGraphicsState()
}

func text(_ value: String, x: CGFloat, y: CGFloat, size: CGFloat, color: NSColor, bold: Bool = false) {
    (value as NSString).draw(at: NSPoint(x: x, y: y), withAttributes: [
        .font: NSFont.systemFont(ofSize: size, weight: bold ? .semibold : .regular),
        .foregroundColor: color,
    ])
}

func makeProposals(in directory: URL) throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let palettes = [IconPalette.original] + IconPalette.darkProposals
    for palette in palettes {
        let destination = directory.appendingPathComponent(palette.id)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for size in [88, 176, 512, 1024] {
            try png(width: size, height: size) { drawIcon(side: CGFloat(size), palette: palette) }
                .write(to: destination.appendingPathComponent("app-\(size).png"))
        }
    }
    let board = png(width: 1440, height: 820) {
        NSColor(srgbRed: 0.94, green: 0.95, blue: 0.97, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 1440, height: 820).fill()
        text("Logo original · variantes pour le mode sombre", x: 36, y: 752, size: 28, color: .black, bold: true)
        text("Même dessin à deux flèches · trois palettes à comparer", x: 36, y: 719, size: 16, color: .darkGray)
        for (index, palette) in palettes.enumerated() {
            let x = CGFloat(30 + index * 352)
            text(palette.name, x: x + 8, y: 659, size: 21, color: .black, bold: true)
            let darkCard = NSBezierPath(roundedRect: NSRect(x: x, y: 285, width: 324, height: 350), xRadius: 20, yRadius: 20)
            NSColor(srgbRed: 0.12, green: 0.12, blue: 0.13, alpha: 1).setFill()
            darkCard.fill()
            text("SUR FOND SOMBRE", x: x + 22, y: 598, size: 11, color: .lightGray, bold: true)
            drawPreview(palette, rect: NSRect(x: x + 58, y: 380, width: 208, height: 208))
            text("About / GitHub", x: x + 22, y: 316, size: 13, color: .lightGray)
            let lightCard = NSBezierPath(roundedRect: NSRect(x: x, y: 70, width: 324, height: 200), xRadius: 20, yRadius: 20)
            NSColor.white.setFill()
            lightCard.fill()
            text("SUR FOND CLAIR", x: x + 22, y: 234, size: 11, color: .darkGray, bold: true)
            drawPreview(palette, rect: NSRect(x: x + 30, y: 106, width: 120, height: 120))
            drawPreview(palette, rect: NSRect(x: x + 197, y: 122, width: 88, height: 88))
            text("88 pt", x: x + 220, y: 94, size: 11, color: .darkGray)
        }
        text("Palettes dessinées avec AppKit · logo clair conservé · aucune variante sombre appliquée", x: 36, y: 24, size: 14, color: .darkGray)
    }
    try board.write(to: directory.appendingPathComponent("comparison.png"))
    print("Dark logo proposals: \(directory.path)")
}

func makeSelectedAssets(in directory: URL) throws {
    NSApplication.shared.setActivationPolicy(.prohibited)
    for (name, palette) in [("light", IconPalette.original), ("dark", .dark)] {
        let destination = directory.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for size in [88, 176, 512, 1024] {
            try png(width: size, height: size) { drawIcon(side: CGFloat(size), palette: palette) }
                .write(to: destination.appendingPathComponent("app-\(size).png"))
        }
    }
    let board = png(width: 800, height: 450) {
        for (x, palette, background, foreground, label) in [
            (CGFloat(0), IconPalette.original, NSColor.white, NSColor.black, "Mode clair · original"),
            (CGFloat(400), .dark, NSColor(srgbRed: 0.12, green: 0.12, blue: 0.13, alpha: 1), .white, "Mode sombre · bleu profond"),
        ] {
            background.setFill()
            NSRect(x: x, y: 0, width: 400, height: 450).fill()
            drawPreview(palette, rect: NSRect(x: x + 72, y: 122, width: 256, height: 256))
            text(label, x: x + 42, y: 66, size: 20, color: foreground, bold: true)
            text(palette.id == "original" ? "Flèches blanches" : "Flèches noires", x: x + 42, y: 35, size: 15, color: foreground)
        }
    }
    try board.write(to: directory.appendingPathComponent("comparison.png"))
    print("Selected light/dark logo assets: \(directory.path)")
}

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.count == 2 && arguments[0] == "--proposals" {
    try makeProposals(in: URL(fileURLWithPath: arguments[1]))
} else if arguments.count == 2 && arguments[0] == "--dark" {
    try makeProductionIcon(at: URL(fileURLWithPath: arguments[1]), palette: .dark)
} else if arguments.count == 2 && arguments[0] == "--selected-assets" {
    try makeSelectedAssets(in: URL(fileURLWithPath: arguments[1]))
} else if arguments.count == 1 && !arguments[0].hasPrefix("--") {
    try makeProductionIcon(at: URL(fileURLWithPath: arguments[0]))
} else {
    fputs("Usage: make-icon.swift OUTPUT.icns | --dark OUTPUT.icns | --proposals DIRECTORY | --selected-assets DIRECTORY\n", stderr)
    exit(2)
}
