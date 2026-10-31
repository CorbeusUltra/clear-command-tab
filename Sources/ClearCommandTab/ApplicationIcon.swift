import AppKit
import CryptoKit
import Darwin
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Quick Look honors the system's icon/widget style (including automatic dark
/// icons). A named DarkAqua drawing appearance alone does not do that for file
/// icons. This cache is in memory only and never blocks an icon worker waiting
/// for the Quick Look service.
final class ApplicationIconStyler: @unchecked Sendable {
    typealias Generator = (URL, Int, @escaping (CGImage?) -> Void) -> Void
    private struct Key: Hashable {
        let url: URL
        let pixels: Int
        let appearance: String
        let artwork: Data
    }
    private struct Entry {
        let image: CGImage
        let expiry: TimeInterval
        var access: UInt64
    }
    private final class Pending {
        var completions: [(CGImage) -> Void] = []
    }
    private let lock = NSLock()
    private var entries: [Key: Entry] = [:]
    private var pending: [Key: Pending] = [:]
    private var access: UInt64 = 0
    private var revision: UInt64 = 0
    private let generator: Generator
    private let clock: () -> TimeInterval
    private let lifetime: TimeInterval
    private let byteLimit: Int

    init(lifetime: TimeInterval = 5, byteLimit: Int = 16 * 1024 * 1024,
         clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime },
         generator: @escaping Generator = ApplicationIconStyler.generate) {
        self.lifetime = lifetime
        self.byteLimit = byteLimit
        self.clock = clock
        self.generator = generator
    }

    func invalidate() {
        lock.lock()
        revision &+= 1
        entries.removeAll(keepingCapacity: true)
        // Already-issued requests still complete their own callers, but cannot
        // populate the new appearance's cache or accept new coalesced callers.
        pending.removeAll(keepingCapacity: true)
        lock.unlock()
    }

    var generation: UInt64 {
        lock.lock(); defer { lock.unlock() }
        return revision
    }

    /// The caller has already checked that this is bundle artwork, not a custom
    /// runtime image. Changes to the source pixels also change the cache key.
    func image(for url: URL, base: CGImage, pixels: Int, appearance: NSAppearance.Name,
               generation: UInt64? = nil,
               completion: @escaping (CGImage) -> Void) {
        guard let data = base.dataProvider?.data else { completion(base); return }
        let key = Key(url: url.standardizedFileURL, pixels: pixels, appearance: appearance.rawValue,
                      artwork: Data(SHA256.hash(data: data as Data)))
        let now = clock()
        lock.lock()
        if let generation, generation != revision {
            lock.unlock()
            completion(base)
            return
        }
        access &+= 1
        if var entry = entries[key], entry.expiry > now {
            entry.access = access
            entries[key] = entry
            lock.unlock()
            completion(entry.image)
            return
        }
        if let request = pending[key] {
            request.completions.append(completion)
            lock.unlock()
            return
        }
        let request = Pending()
        request.completions.append(completion)
        pending[key] = request
        lock.unlock()
        generator(url, pixels) { [self] generated in
            let image = generated.flatMap { ApplicationIcon.resize($0, pixels: pixels) } ?? base
            lock.lock()
            if pending[key] === request {
                pending[key] = nil
                access &+= 1
                // Cache failures briefly too, preserving correct base artwork
                // without repeatedly asking a failing service on every tick.
                entries[key] = Entry(image: image, expiry: clock() + lifetime, access: access)
                var bytes = entries.values.reduce(0) { $0 + $1.image.bytesPerRow * $1.image.height }
                while entries.count > 64 || bytes > byteLimit {
                    guard let oldest = entries.min(by: { $0.value.access < $1.value.access }) else { break }
                    bytes -= oldest.value.image.bytesPerRow * oldest.value.image.height
                    entries[oldest.key] = nil
                }
            }
            let completions = request.completions
            request.completions.removeAll()
            lock.unlock()
            for complete in completions { complete(image) }
        }
    }

    private static func generate(_ url: URL, _ pixels: Int, completion: @escaping (CGImage?) -> Void) {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: pixels, height: pixels),
                                                   scale: 1, representationTypes: .icon)
        request.iconMode = true
        let gate = GenerationCompletion(completion)
        let timeout = DispatchWorkItem {
            if gate.finish(nil) { QLThumbnailGenerator.shared.cancel(request) }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 2, execute: timeout)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            let image = representation?.cgImage
            DispatchQueue.global(qos: .utility).async {
                if gate.finish(image) { timeout.cancel() }
            }
        }
    }

    private final class GenerationCompletion: @unchecked Sendable {
        private let lock = NSLock()
        private var completion: ((CGImage?) -> Void)?
        init(_ completion: @escaping (CGImage?) -> Void) { self.completion = completion }
        @discardableResult func finish(_ image: CGImage?) -> Bool {
            lock.lock()
            let callback = completion
            completion = nil
            lock.unlock()
            callback?(image)
            return callback != nil
        }
    }
}

/// Positive discoveries only; nil is deliberately retried as Python loads its
/// backend. A launch date prevents reuse of a previous process's resource.
final class MatplotlibResourceCache: @unchecked Sendable {
    private struct Entry { let launch: Date; let url: URL }
    private let lock = NSLock()
    private var entries: [Int32: Entry] = [:]

    func resource(pid: Int32, launch: Date?, discover: () -> URL?) -> URL? {
        guard let launch else { return discover() }
        lock.lock()
        let cached = entries[pid].flatMap { $0.launch == launch ? $0.url : nil }
        lock.unlock()
        if let cached { return cached }
        guard let url = discover() else { return nil }
        lock.lock()
        // A bounded process cache, not a durable record of interpreter paths.
        if entries.count >= 128 { entries.removeAll(keepingCapacity: true) }
        entries[pid] = Entry(launch: launch, url: url)
        lock.unlock()
        return url
    }

    func forget(_ pid: Int32) { lock.lock(); entries[pid] = nil; lock.unlock() }
    func retain(_ pids: Set<Int32>) {
        lock.lock(); entries = entries.filter { pids.contains($0.key) }; lock.unlock()
    }
}

enum ApplicationIcon {
    private static let matplotlibResources = MatplotlibResourceCache()
    static func forgetResources(for pid: Int32) { matplotlibResources.forget(pid) }
    static func retainResources(for pids: Set<Int32>) { matplotlibResources.retain(pids) }
    /// Rasterize the supplied app artwork without cropping its native optical margin.
    /// This avoids drawing vector/custom NSImage representations directly in the panel.
    static func rasterize(_ image: NSImage?, pixels: Int = 320, appearance: NSAppearance? = nil) -> CGImage? {
        if let appearance {
            var result: CGImage?
            appearance.performAsCurrentDrawingAppearance { result = rasterize(image, pixels: pixels) }
            return result
        }
        guard let original = image, let image = original.copy() as? NSImage else { return nil }
        // NSRunningApplication can return the same NSImage again. Do not freeze a
        // custom drawing representation in a cached CGImage between refreshes.
        // Copy first: never change the cache policy of the shared source image.
        image.cacheMode = .never
        var rect = CGRect(x: 0, y: 0, width: pixels, height: pixels)
        let hints: [NSImageRep.HintKey: Any] = [.interpolation: NSImageInterpolation.high.rawValue]
        guard let source = image.cgImage(forProposedRect: &rect, context: nil, hints: hints) else { return nil }
        return resize(source, pixels: pixels)
    }

    static func resize(_ source: CGImage, pixels: Int) -> CGImage? {
        guard let context = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8,
                                      bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(source, in: CGRect(x: 0, y: 0, width: pixels, height: pixels))
        return context.makeImage()
    }

    static func resolve(_ app: NSRunningApplication, pixels: Int, appearance: NSAppearance? = nil) -> CGImage? {
        if let appearance {
            var result: CGImage?
            // Asset lookup as well as rasterization must use the captured appearance,
            // including when this runs on the utility queue rather than in a view.
            appearance.performAsCurrentDrawingAppearance { result = resolve(app, pixels: pixels) }
            return result
        }
        // Re-query the public process record rather than treating its first icon
        // as permanent. This is application artwork, not a remote Dock contentView.
        let current = NSRunningApplication(processIdentifier: app.processIdentifier)
        let reported = (current == app ? current?.icon : nil) ?? app.icon
        // Standalone Python interpreters can report a valid generic document icon,
        // even after Matplotlib sets NSApplication.applicationIconImage. Treat only
        // that placeholder as missing; preserve artwork supplied by other GUI apps.
        if isPythonExecutable(app.executableURL), isMissingOrGenericDocument(reported),
           let resource = matplotlibResources.resource(pid: app.processIdentifier, launch: app.launchDate,
                discover: { matplotlibIconResource(processIdentifier: app.processIdentifier) }) {
            if let image = rasterize(NSImage(contentsOf: resource), pixels: pixels) { return image }
            // A moved/deleted environment must not pin a failed positive lookup.
            matplotlibResources.forget(app.processIdentifier)
        }
        if let image = rasterize(reported, pixels: pixels) { return image }
        // Use the actual executable's enclosing app bundle, never an unrelated interpreter logo.
        return bundleURL(for: app).flatMap { rasterize(NSWorkspace.shared.icon(forFile: $0.path), pixels: pixels) }
    }

    private static func bundleURL(for app: NSRunningApplication) -> URL? {
        var bundle = app.bundleURL.flatMap { $0.pathExtension == "app" ? $0 : nil }
        if bundle == nil, var candidate = app.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent() {
            while candidate.path != "/" {
                if candidate.pathExtension == "app" { bundle = candidate; break }
                candidate.deleteLastPathComponent()
            }
        }
        return bundle
    }

    /// Only style ordinary bundle artwork. Preserve a runtime replacement and
    /// the Matplotlib fallback rather than overwriting either with a file icon.
    static func styleBundleURL(for app: NSRunningApplication, matching image: CGImage,
                               pixels: Int, appearance: NSAppearance) -> URL? {
        guard let bundle = bundleURL(for: app) else { return nil }
        var fileIcon: CGImage?
        appearance.performAsCurrentDrawingAppearance {
            fileIcon = rasterize(NSWorkspace.shared.icon(forFile: bundle.path), pixels: pixels)
        }
        return samePixels(image, fileIcon) ? bundle : nil
    }

    static func isPythonExecutable(_ executable: URL?) -> Bool {
        guard let name = executable?.resolvingSymlinksInPath().lastPathComponent else { return false }
        return name.range(of: #"^pythonw?(?:[0-9]+(?:\.[0-9]+)*)?t?$"#,
                          options: .regularExpression) != nil
    }

    /// Compare only immutable raster output, on the utility queue. A periodic
    /// read of unchanged artwork must not trigger another panel redraw.
    static func samePixels(_ lhs: CGImage?, _ rhs: CGImage?) -> Bool {
        guard let lhs, let rhs else { return lhs == nil && rhs == nil }
        if lhs === rhs { return true }
        guard lhs.width == rhs.width, lhs.height == rhs.height,
              lhs.bytesPerRow == rhs.bytesPerRow, lhs.bitmapInfo == rhs.bitmapInfo,
              let left = lhs.dataProvider?.data, let right = rhs.dataProvider?.data else { return false }
        return (left as Data) == (right as Data)
    }

    private static let genericDocument = NSWorkspace.shared.icon(for: .data)

    static func isMissingOrGenericDocument(_ image: NSImage?) -> Bool {
        guard let image else { return true }
        guard let candidate = rasterize(image, pixels: 32)?.dataProvider?.data,
              let reference = rasterize(genericDocument, pixels: 32)?.dataProvider?.data else { return false }
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

    // NSApplicationIcon is this process's own logo. A missing third-party image
    // must use the generic application symbol, never impersonate ClearCommandTab.
    static let fallback = rasterize(NSWorkspace.shared.icon(for: .applicationBundle))
}
