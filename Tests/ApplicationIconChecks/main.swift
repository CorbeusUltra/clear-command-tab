import AppKit
import CryptoKit

// Compile with the production ApplicationIcon.swift. No windows, input or Python
// execution: optional arguments inspect an already-running Matplotlib process.
var failures = 0
var count = 0
func check(_ condition: Bool, _ label: String) {
    count += 1
    if !condition { failures += 1 }
    print("\(condition ? "PASS" : "FAIL") \(label)")
}
func digest(_ image: CGImage?) -> String? {
    image?.dataProvider?.data.map { SHA256.hash(data: $0 as Data).description }
}

check(ApplicationIcon.isMissingOrGenericDocument(nil), "missing artwork permits fallback")
check(ApplicationIcon.isMissingOrGenericDocument(NSWorkspace.shared.icon(for: .data)),
      "system document placeholder permits fallback")
let context = CGContext(data: nil, width: 32, height: 32, bitsPerComponent: 8,
                        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
context.fill(CGRect(x: 0, y: 0, width: 32, height: 32))
let custom = NSImage(cgImage: context.makeImage()!, size: NSSize(width: 32, height: 32))
check(!ApplicationIcon.isMissingOrGenericDocument(custom), "custom GUI artwork is preserved")
NSApplication.shared.setActivationPolicy(.prohibited)
NSApplication.shared.applicationIconImage = custom
check(ApplicationIcon.samePixels(ApplicationIcon.fallback,
      ApplicationIcon.rasterize(NSWorkspace.shared.icon(for: .applicationBundle))),
      "missing third-party artwork uses a generic app symbol, never the current app's own icon")
let adaptive = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
    let dark = NSAppearance.currentDrawing().bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    (dark ? NSColor.black : NSColor.white).setFill()
    rect.fill()
    return true
}
let aqua = NSAppearance(named: .aqua)!, dark = NSAppearance(named: .darkAqua)!
let lightArtwork = digest(ApplicationIcon.rasterize(adaptive, pixels: 32, appearance: aqua))
let darkArtwork = digest(ApplicationIcon.rasterize(adaptive, pixels: 32, appearance: dark))
check(lightArtwork != nil && darkArtwork != nil && lightArtwork != darkArtwork,
      "same adaptive image resolves distinct light and dark artwork")
check(digest(ApplicationIcon.rasterize(adaptive, pixels: 32, appearance: aqua)) == lightArtwork,
      "dark-to-light rasterization restores the light artwork")
var liveColor = NSColor.red
let liveArtwork = NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
    liveColor.setFill(); rect.fill(); return true
}
let firstLive = ApplicationIcon.rasterize(liveArtwork, pixels: 32, appearance: aqua)
liveColor = .blue
let secondLive = ApplicationIcon.rasterize(liveArtwork, pixels: 32, appearance: aqua)
check(!ApplicationIcon.samePixels(firstLive, secondLive), "same dynamic image is redrawn after its content changes")
check(ApplicationIcon.samePixels(secondLive, ApplicationIcon.rasterize(liveArtwork, pixels: 32, appearance: aqua)),
      "unchanged dynamic pixels compare equal without requiring image identity")
check(!ApplicationIcon.samePixels(firstLive, nil), "missing refresh is not equivalent to existing valid artwork")
for name in ["python", "python3", "python3.13", "python3.13t", "pythonw"] {
    check(ApplicationIcon.isPythonExecutable(URL(fileURLWithPath: "/nonexistent/\(name)")), "recognize \(name)")
}
for name in ["ipython", "python-helper", "python3.app", "ruby"] {
    check(!ApplicationIcon.isPythonExecutable(URL(fileURLWithPath: "/nonexistent/\(name)")), "exclude \(name)")
}
let package = "/environment/site-packages/matplotlib"
for name in ["_macosx.so", "_macosx.cpython-313-darwin.so"] {
    check(ApplicationIcon.matplotlibIconResource(mappedBackendPath: "\(package)/backends/\(name)")?.path
          == "\(package)/mpl-data/images/matplotlib.pdf", "derive artwork from loaded \(name)")
}
for path in ["\(package)/__init__.py", "\(package)/backends/_tkagg.so",
             "/environment/other/backends/_macosx.so", "\(package)/other/_macosx.so",
             "matplotlib/backends/_macosx.so"] {
    check(ApplicationIcon.matplotlibIconResource(mappedBackendPath: path) == nil,
          "reject non-native-backend path \(path)")
}
check(ApplicationIcon.matplotlibIconResource(processIdentifier: -1) == nil,
      "unavailable process falls back safely")

let resources = MatplotlibResourceCache()
let launch = Date(timeIntervalSinceReferenceDate: 1)
let resource = URL(fileURLWithPath: "\(package)/mpl-data/images/matplotlib.pdf")
var discoveries = 0
func discoverResource() -> URL? { discoveries += 1; return resource }
check(resources.resource(pid: 1, launch: launch, discover: { nil }) == nil,
      "an early missing backend is not cached")
check(resources.resource(pid: 1, launch: launch, discover: discoverResource) == resource,
      "a backend loaded after an early miss is discovered")
_ = resources.resource(pid: 1, launch: launch, discover: discoverResource)
check(discoveries == 1, "positive Matplotlib discovery avoids repeated libproc walks")
_ = resources.resource(pid: 1, launch: launch.addingTimeInterval(1), discover: discoverResource)
check(discoveries == 2, "PID reuse with a new launch date forces resource discovery")
resources.retain([])
_ = resources.resource(pid: 1, launch: launch, discover: discoverResource)
check(discoveries == 3, "retiring a process removes its positive resource cache")
resources.forget(1)
_ = resources.resource(pid: 1, launch: launch, discover: discoverResource)
check(discoveries == 4, "invalidated resource is discoverable again")
_ = resources.resource(pid: 2, launch: nil, discover: discoverResource)
_ = resources.resource(pid: 2, launch: nil, discover: discoverResource)
check(discoveries == 6, "unknown process creation identity never reuses a resource across PIDs")

// The system icon/widget style is separate from NSAppearance. Exercise the
// asynchronous styling layer without changing system preferences or using QL.
let styleURL = URL(fileURLWithPath: "/fixtures/Arbitrary.app")
let styleBase = firstLive!, styleNewBase = secondLive!
var styleTime: TimeInterval = 0
var styleRequests: [(CGImage?) -> Void] = []
let styler = ApplicationIconStyler(clock: { styleTime }, generator: { _, _, complete in styleRequests.append(complete) })
var styledResults: [CGImage] = []
func requestStyle(_ appearance: NSAppearance.Name = .aqua, base: CGImage? = nil, generation: UInt64? = nil) {
    styler.image(for: styleURL, base: base ?? styleBase, pixels: 32, appearance: appearance,
                 generation: generation) { styledResults.append($0) }
}
requestStyle()
requestStyle()
check(styleRequests.count == 1 && styledResults.isEmpty, "concurrent native style requests coalesce without blocking")
styleRequests[0](styleNewBase)
check(styledResults.count == 2 && styledResults.allSatisfy { ApplicationIcon.samePixels($0, styleNewBase) },
      "coalesced native requests receive the generated artwork")
requestStyle()
check(styleRequests.count == 1 && styledResults.count == 3, "warm style cache avoids another Quick Look request")
requestStyle(.darkAqua)
check(styleRequests.count == 2, "different drawing appearances do not share a styled bitmap")
styleRequests[1](styleNewBase)
requestStyle(.aqua, base: styleNewBase)
check(styleRequests.count == 3, "source pixel changes invalidate styled artwork even for the same bundle")
styleRequests[2](styleBase)
styleTime = 6
requestStyle()
check(styleRequests.count == 4, "visible refresh can discover an independent icon-style change after bounded cache expiry")
styleRequests[3](nil)
check(ApplicationIcon.samePixels(styledResults.last, styleBase), "native rendering failure retains correct base artwork")
requestStyle()
check(styleRequests.count == 4, "native failure is briefly cached to avoid repeatedly calling a failing service")
styleTime = 12
requestStyle()
check(styleRequests.count == 5, "native rendering recovers after a cached failure expires")
let staleGeneration = styler.generation
styler.invalidate()
requestStyle()
check(styleRequests.count == 6, "appearance invalidation starts a new request instead of coalescing behind stale work")
styleRequests[4](styleBase)
styleRequests[5](styleNewBase)
requestStyle()
check(styleRequests.count == 6 && ApplicationIcon.samePixels(styledResults.last, styleNewBase),
      "old appearance completion cannot overwrite the new native style cache")
requestStyle(generation: staleGeneration)
check(styleRequests.count == 6 && ApplicationIcon.samePixels(styledResults.last, styleBase),
      "a queued request captured before invalidation never starts stale native rendering")
var evictedRequests = 0
let tinyCache = ApplicationIconStyler(byteLimit: 1, generator: { _, _, complete in
    evictedRequests += 1; complete(styleNewBase)
})
for _ in 0..<2 { tinyCache.image(for: styleURL, base: styleBase, pixels: 32, appearance: .aqua) { _ in } }
check(evictedRequests == 2, "native style cache respects its pixel memory limit")
if let running = NSWorkspace.shared.runningApplications.first(where: { $0.activationPolicy == .regular && !$0.isTerminated }) {
    check(ApplicationIcon.styleBundleURL(for: running, matching: styleBase, pixels: 32, appearance: aqua) == nil,
          "a custom runtime image is never replaced by themed bundle artwork")
}

if CommandLine.arguments.count == 3, let pid = Int32(CommandLine.arguments[1]),
   let app = NSRunningApplication(processIdentifier: pid) {
    let name = app.localizedName
    let expectedResource = URL(fileURLWithPath: CommandLine.arguments[2])
    check(ApplicationIcon.isMissingOrGenericDocument(app.icon), "live Python reports placeholder")
    check(ApplicationIcon.matplotlibIconResource(processIdentifier: pid) == expectedResource,
          "live loaded backend identifies its own environment")
    let expected = ApplicationIcon.rasterize(NSImage(contentsOf: expectedResource), pixels: 320)
    let start = ProcessInfo.processInfo.systemUptime
    let resolved = ApplicationIcon.resolve(app, pixels: 320)
    print("Live resolution milliseconds: \((ProcessInfo.processInfo.systemUptime - start) * 1000)")
    check(expected != nil && digest(resolved) == digest(expected), "live resolution matches Matplotlib artwork")
    check(digest(resolved) != digest(ApplicationIcon.rasterize(app.icon)), "live result replaces white document")
    check(app.localizedName == name, "live process name remains unchanged")
} else if CommandLine.arguments.count != 1 {
    check(false, "expected a running process ID and its Matplotlib artwork path")
}
print("\(count) checks, \(failures) failed assertions")
exit(failures == 0 ? 0 : 1)
