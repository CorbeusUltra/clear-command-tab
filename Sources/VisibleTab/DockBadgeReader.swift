import AppKit
import ApplicationServices
import VisibleTabCore

/// Dock accessibility exposes the badge the user actually sees, including symbols.
/// All IPC stays off the keyboard callback and the main thread. No idle polling.
final class DockBadgeReader {
    private let queue = DispatchQueue(label: "local.lucas.VisibleTab.badges", qos: .utility)
    private var bundleIDs: [URL: String] = [:] // confined to queue

    func read(dockPID: pid_t, completion: @escaping ([String: String]) -> Void) {
        queue.async { [self] in
            let badges = snapshot(dockPID: dockPID)
            DispatchQueue.main.async { completion(badges) }
        }
    }

    // Also used by the read-only diagnostic command.
    func snapshot(dockPID: pid_t) -> [String: String] {
        let root = AXUIElementCreateApplication(dockPID)
        AXUIElementSetMessagingTimeout(root, 0.1)
        let deadline = Date().addingTimeInterval(0.6)
        var remaining = 256
        var result: [String: String] = [:]
        func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
            AXUIElementSetMessagingTimeout(element, 0.1)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
            return value
        }
        func visit(_ element: AXUIElement, depth: Int) {
            guard depth <= 3, remaining > 0, Date() < deadline else { return }
            remaining -= 1
            if attribute(element, kAXRoleAttribute) as? String == "AXDockItem" {
                guard attribute(element, kAXSubroleAttribute) as? String == "AXApplicationDockItem",
                      let text = BadgeText.normalized(attribute(element, "AXStatusLabel") as? String),
                      let url = attribute(element, "AXURL") as? URL else { return }
                let id = bundleIDs[url] ?? Bundle(url: url)?.bundleIdentifier
                if let id { bundleIDs[url] = id; result[id] = text }
                return
            }
            let children = attribute(element, kAXChildrenAttribute) as? [AXUIElement] ?? []
            for child in children { visit(child, depth: depth + 1) }
        }
        visit(root, depth: 0)
        return result
    }
}
