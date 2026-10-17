import AppKit
import Darwin

// Measures the real hidden AppKit panel. This is preparation latency, not physical
// key-to-photon latency: no event tap, compositor presentation, or app activation.
let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
func cpuSeconds() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
        + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
}
func percentile(_ values: [Double], _ fraction: Double) -> Double {
    let sorted = values.sorted()
    return sorted[min(sorted.count - 1, Int(Double(sorted.count - 1) * fraction))]
}
var measurements: [[String: Any]] = []
MainActor.assumeIsolated {
    guard let screen = NSScreen.main else { fatalError("A macOS display session is required") }
    let context = CGContext(data: nil, width: 64, height: 64, bitsPerComponent: 8,
        bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 64, height: 64))
    let icon = context.makeImage()!
    for count in [3, 18, 50] {
        let panel = SwitcherPanel()
        panel.applyGlassProfile(.matte)
        let items = (0..<count).map { index in
            SwitcherItem(id: .application(Int32(index + 1)), name: "Fixture \(index)", icon: icon,
                         badge: index % 3 == 0 ? "2" : nil, windowTitle: "Document \(index)")
        }
        for index in 0..<100 { panel.prepare(items: items, selected: items[index % count].id, screen: screen) }
        let startCPU = cpuSeconds()
        let start = ProcessInfo.processInfo.systemUptime
        var samples: [Double] = []
        for index in 0..<2000 {
            autoreleasepool {
                let before = ProcessInfo.processInfo.systemUptime
                panel.prepare(items: items, selected: items[index % count].id, screen: screen)
                samples.append((ProcessInfo.processInfo.systemUptime - before) * 1000)
            }
        }
        measurements.append(["scenario": "cached-window-navigation", "items": count, "iterations": samples.count,
            "p50Ms": percentile(samples, 0.50), "p95Ms": percentile(samples, 0.95),
            "cpuSeconds": cpuSeconds() - startCPU, "wallSeconds": ProcessInfo.processInfo.systemUptime - start])
        precondition(!panel.isVisible, "Benchmark must never present the switcher")
    }
}
var usage = rusage()
getrusage(RUSAGE_SELF, &usage)
let report: [String: Any] = ["measurements": measurements, "peakRSSBytes": usage.ru_maxrss,
    "os": ProcessInfo.processInfo.operatingSystemVersionString, "swiftMode": "release",
    "measurementBoundary": "cached items -> real AppKit panel prepared; no presentation or focus"]
let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
if CommandLine.arguments.count == 2 { try data.write(to: URL(fileURLWithPath: CommandLine.arguments[1])) }
print(String(decoding: data, as: UTF8.self))
