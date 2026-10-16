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
