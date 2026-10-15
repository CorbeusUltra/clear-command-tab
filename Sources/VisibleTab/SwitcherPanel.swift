import AppKit
import VisibleTabCore

@MainActor
struct SwitcherItem {
    let id: Int32
    let name: String
    let icon: NSImage?
    var badge: String? = nil
}

@MainActor
final class SwitcherPanel: NSPanel {
    var onSelect: ((Int32, Bool) -> Void)?
    private let surface: NSView
    private let canvas = NSView()
    private let scroll = NSScrollView()
    private let row = NSView()
    private let selectionHighlight = NSVisualEffectView()
    private let nameLabel = NSTextField(labelWithString: "")
    private var cells: [Int32: ApplicationCell] = [:]
    private var displayedIDs: [Int32] = []
    private var layout: SwitcherLayout?
    private var selectedIndex: Int?
    private var scrollObserver: NSObjectProtocol?
    private var pointer = PointerMotionGate()

    // Clear glass switches to a subdued opaque appearance in a non-key window.
    // A nonactivating panel may take keyboard focus without activating its app.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func animationResizeTime(_ newFrame: NSRect) -> TimeInterval { 0.12 }

    init() {
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            // Public clear glass preserves backdrop detail and native edge refraction.
            glass.style = .clear
            glass.tintColor = nil
            surface = glass
        } else {
            let blur = NSVisualEffectView()
            blur.material = .hudWindow
            blur.blendingMode = .behindWindow
            blur.state = .active
            blur.wantsLayer = true
            surface = blur
        }
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        title = "VisibleTab"
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        hidesOnDeactivate = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .transient]
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        acceptsMouseMovedEvents = true
        animationBehavior = .none
        canvas.autoresizingMask = [.width, .height]
        if #available(macOS 26.0, *), let glass = surface as? NSGlassEffectView {
            // The public API must own its content. Layer masking or placing an unrelated
            // blur behind it would clip/suppress the glass rim and its native refraction.
            glass.contentView = canvas
        } else {
            surface.addSubview(canvas)
        }
        contentView = surface
        scroll.drawsBackground = false
        scroll.contentView.drawsBackground = false
        scroll.hasHorizontalScroller = false
        scroll.hasVerticalScroller = false
        scroll.horizontalScrollElasticity = .none
        scroll.verticalScrollElasticity = .none
        scroll.documentView = row
        // Let AppKit render a neutral selection material over the actual backdrop.
        // A separate sibling behind the icon avoids applying vibrancy to app artwork.
        selectionHighlight.material = .selection
        selectionHighlight.blendingMode = .withinWindow
        selectionHighlight.state = .active
        selectionHighlight.isEmphasized = false
        selectionHighlight.wantsLayer = true
        selectionHighlight.layer?.masksToBounds = true
        selectionHighlight.isHidden = true
        row.addSubview(selectionHighlight)
        scroll.contentView.postsBoundsChangedNotifications = true
        canvas.addSubview(scroll)
        nameLabel.alignment = .center
        nameLabel.textColor = .labelColor
        nameLabel.lineBreakMode = .byTruncatingTail
        canvas.addSubview(nameLabel)
        scrollObserver = NotificationCenter.default.addObserver(
            forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.positionCaption() }
        }
        setAccessibilityLabel("VisibleTab application switcher")
    }

    func display(ids: [Int32], selected: Int32?, tracker: ApplicationTracker,
                 badges: [String: String], screen: NSScreen) {
        let items = ids.map {
            SwitcherItem(id: $0, name: tracker.applications[$0]?.localizedName ?? "Application",
                         icon: tracker.icons[$0], badge: tracker.applications[$0]?.bundleIdentifier.flatMap { badges[$0] })
        }
        display(items: items, selected: selected, screen: screen)
    }

    func display(items: [SwitcherItem], selected: Int32?, screen: NSScreen) {
        if !isVisible {
            pointer.reset(at: NSEvent.mouseLocation)
        }
        guard let newLayout = SwitcherLayout(applicationCount: items.count, availableSize: screen.visibleFrame.size) else {
            orderOut(nil)
            return
        }
        let frame = NSRect(x: screen.frame.midX - newLayout.size.width / 2,
                           y: screen.frame.midY - newLayout.size.height / 2,
                           width: newLayout.size.width, height: newLayout.size.height)
        if self.frame != frame {
            let animate = isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            setFrame(frame, display: false, animate: animate)
        }
        layout = newLayout
        surface.frame = NSRect(origin: .zero, size: newLayout.size)
        canvas.frame = surface.bounds
        if #available(macOS 26.0, *), let glass = surface as? NSGlassEffectView {
            glass.cornerRadius = newLayout.cornerRadius
        } else {
            surface.layer?.cornerRadius = newLayout.cornerRadius
            surface.layer?.masksToBounds = true
        }
        scroll.frame = NSRect(x: newLayout.horizontalInset, y: newLayout.rowBottom,
                              width: newLayout.viewportWidth, height: newLayout.tileSize)
        let ids = items.map(\.id)
        if displayedIDs != ids {
            for cell in cells.values { cell.removeFromSuperview() }
            cells.removeAll()
            for item in items {
                let cell = ApplicationCell(item: item)
                cell.onSelect = { [weak self] id, activate in self?.onSelect?(id, activate) }
                cell.onMotion = { [weak self] id, point in
                    guard let self, self.pointer.accept(point) else { return }
                    self.onSelect?(id, false)
                }
                row.addSubview(cell)
                cells[item.id] = cell
            }
            displayedIDs = ids
        }
        row.frame = NSRect(x: 0, y: 0, width: newLayout.documentWidth, height: newLayout.tileSize)
        for (index, id) in ids.enumerated() {
            guard let cell = cells[id] else { continue }
            cell.item = items[index]
            cell.frame = newLayout.tileFrame(at: index)
            cell.isSelected = id == selected
        }
        selectedIndex = selected.flatMap { ids.firstIndex(of: $0) }
        if let selected, let cell = cells[selected] {
            let inset = max(1, newLayout.tileSize / 144)
            selectionHighlight.frame = cell.frame.insetBy(dx: inset, dy: inset)
            selectionHighlight.layer?.cornerRadius = newLayout.tileSize * 0.27
            selectionHighlight.isHidden = false
        } else { selectionHighlight.isHidden = true }
        nameLabel.font = .systemFont(ofSize: newLayout.labelFontSize, weight: .semibold)
        nameLabel.stringValue = selected.flatMap { id in items.first { $0.id == id }?.name } ?? ""
        if let selected, let cell = cells[selected] { row.scrollToVisible(cell.frame) }
        positionCaption()
        if !isKeyWindow { makeKeyAndOrderFront(nil) }
        else { orderFrontRegardless() }
    }

    private func positionCaption() {
        guard let layout, let selectedIndex else { nameLabel.isHidden = true; return }
        nameLabel.isHidden = false
        let width = (nameLabel.stringValue as NSString).size(withAttributes: [.font: nameLabel.font!]).width
        nameLabel.frame = layout.labelFrame(at: selectedIndex,
                                           scrollOrigin: scroll.contentView.bounds.minX, textWidth: width)
    }

    func containsQuartzPoint(_ point: CGPoint) -> Bool {
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        return isVisible && frame.contains(NSPoint(x: point.x, y: top - point.y))
    }
}

@MainActor
private final class ApplicationCell: NSView {
    var item: SwitcherItem {
        didSet { needsDisplay = true; updateAccessibility() }
    }
    var onSelect: ((Int32, Bool) -> Void)?
    var onMotion: ((Int32, NSPoint) -> Void)?
    var isSelected = false {
        didSet {
            if isSelected != oldValue {
                needsDisplay = true
                updateAccessibility()
            }
        }
    }
    private var tracking: NSTrackingArea?

    init(item: SwitcherItem) {
        self.item = item
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(item.name)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func updateAccessibility() {
        setAccessibilityLabel(item.name)
        setAccessibilityValue([isSelected ? "Selected" : nil,
                               item.badge.map { "Badge: \($0)" }].compactMap { $0 }.joined(separator: ", "))
    }

    override func draw(_ dirtyRect: NSRect) {
        // App icons already include their optical margin; draw the full canvas.
        (item.icon ?? NSImage(named: NSImage.applicationIconName))?.draw(in: bounds,
            from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true,
            hints: [.interpolation: NSImageInterpolation.high])
        if let badge = item.badge {
            let scale = bounds.width / 144
            let font = NSFont.systemFont(ofSize: max(10, 30 * scale), weight: .regular)
            let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white]
            let text = badge as NSString
            let textSize = text.size(withAttributes: attributes)
            let height = max(18, 48 * scale)
            let width = min(bounds.width * 0.7, max(height, textSize.width + 12 * scale))
            let edge = max(1, 2 * scale)
            let rect = NSRect(x: min(bounds.width * 0.86 - width / 2, bounds.maxX - width - edge),
                              y: min(bounds.height * 0.86 - height / 2, bounds.maxY - height - edge),
                              width: width, height: height)
            let capsule = NSBezierPath(roundedRect: rect, xRadius: height / 2, yRadius: height / 2)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowColor = NSColor.black.withAlphaComponent(0.22)
            shadow.shadowBlurRadius = max(0.5, 1.5 * scale)
            shadow.shadowOffset = NSSize(width: 0, height: -scale)
            shadow.set()
            NSColor.systemRed.setFill()
            capsule.fill()
            NSGraphicsContext.restoreGraphicsState()
            NSGradient(starting: NSColor(srgbRed: 1, green: 0.28, blue: 0.24, alpha: 1),
                       ending: NSColor(srgbRed: 0.9, green: 0.14, blue: 0.12, alpha: 1))?.draw(in: capsule, angle: -90)
            let paragraph = NSMutableParagraphStyle()
            paragraph.alignment = .center
            paragraph.lineBreakMode = .byTruncatingTail
            var centered = attributes
            centered[.paragraphStyle] = paragraph
            text.draw(in: NSRect(x: rect.minX + 3 * scale, y: rect.midY - textSize.height / 2,
                                width: rect.width - 6 * scale, height: textSize.height), withAttributes: centered)
        }
    }

    override func updateTrackingAreas() {
        if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: bounds, options: [.mouseMoved, .activeAlways, .inVisibleRect],
                                  owner: self, userInfo: nil)
        if let tracking { addTrackingArea(tracking) }
        super.updateTrackingAreas()
    }

    override func mouseMoved(with event: NSEvent) {
        guard let window else { return }
        onMotion?(item.id, window.convertPoint(toScreen: event.locationInWindow))
    }
    override func mouseDown(with event: NSEvent) { onSelect?(item.id, true) }
    override func accessibilityPerformPress() -> Bool { onSelect?(item.id, true); return true }
}
