import AppKit
import Darwin
import UniformTypeIdentifiers

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
        let reported = app.icon
        // Standalone Python interpreters can report a valid generic document icon,
        // even after Matplotlib sets NSApplication.applicationIconImage. Treat only
        // that placeholder as missing; preserve artwork supplied by other GUI apps.
        if isPythonExecutable(app.executableURL), isMissingOrGenericDocument(reported),
           let resource = matplotlibIconResource(processIdentifier: app.processIdentifier),
           let image = rasterize(NSImage(contentsOf: resource), pixels: pixels) {
            return image
        }
        if let image = rasterize(reported, pixels: pixels) { return image }
        // Use the actual executable's enclosing app bundle, never an unrelated interpreter logo.
        var bundle = app.bundleURL.flatMap { $0.pathExtension == "app" ? $0 : nil }
        if bundle == nil, var candidate = app.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent() {
            while candidate.path != "/" {
                if candidate.pathExtension == "app" { bundle = candidate; break }
                candidate.deleteLastPathComponent()
            }
        }
        return bundle.flatMap { rasterize(NSWorkspace.shared.icon(forFile: $0.path), pixels: pixels) }
    }

    static func isPythonExecutable(_ executable: URL?) -> Bool {
        guard let name = executable?.resolvingSymlinksInPath().lastPathComponent else { return false }
        return name.range(of: #"^pythonw?(?:[0-9]+(?:\.[0-9]+)*)?t?$"#,
                          options: .regularExpression) != nil
    }

    private static let genericDocument = rasterize(NSWorkspace.shared.icon(for: .data), pixels: 32)

    static func isMissingOrGenericDocument(_ image: NSImage?) -> Bool {
        guard let image else { return true }
        guard let candidate = rasterize(image, pixels: 32)?.dataProvider?.data,
              let reference = genericDocument?.dataProvider?.data else { return false }
        return (candidate as Data) == (reference as Data)
    }

    /// Derive artwork only from an actual mapped native Matplotlib backend, never
    /// from a package merely installed alongside an unrelated Python GUI program.
    static func matplotlibIconResource(mappedBackendPath path: String) -> URL? {
        guard path.hasPrefix("/") else { return nil }
        let backend = URL(fileURLWithPath: path)
        let name = backend.lastPathComponent
        guard name == "_macosx.so" || (name.hasPrefix("_macosx.") && name.hasSuffix(".so")),
              backend.deletingLastPathComponent().lastPathComponent == "backends" else { return nil }
        let package = backend.deletingLastPathComponent().deletingLastPathComponent()
        guard package.lastPathComponent == "matplotlib" else { return nil }
        return package.appendingPathComponent("mpl-data/images/matplotlib.pdf")
    }

    /// Read mapped-file metadata with libproc, not process memory. The existing
    /// utility icon queue calls this; it never runs in the keyboard callback.
    /// Failed/early discovery is not cached, so bounded launch retries can recover.
    static func matplotlibIconResource(processIdentifier pid: pid_t) -> URL? {
        var address: UInt64 = 0
        let deadline = ProcessInfo.processInfo.systemUptime + 0.05
        for _ in 0..<8192 {
            guard ProcessInfo.processInfo.systemUptime < deadline else { break }
            var info = proc_regionwithpathinfo()
            let size = MemoryLayout.size(ofValue: info)
            guard proc_pidinfo(pid, PROC_PIDREGIONPATHINFO, address, &info, Int32(size)) == size else { break }
            let capacity = MemoryLayout.size(ofValue: info.prp_vip.vip_path)
            let path = withUnsafePointer(to: &info.prp_vip.vip_path) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { String(cString: $0) }
            }
            if let resource = matplotlibIconResource(mappedBackendPath: path) { return resource }
            let next = info.prp_prinfo.pri_address.addingReportingOverflow(info.prp_prinfo.pri_size)
            guard !next.overflow, next.partialValue > address else { break }
            address = next.partialValue
        }
        return nil
    }

    static let fallback = rasterize(NSImage(named: NSImage.applicationIconName))
}
