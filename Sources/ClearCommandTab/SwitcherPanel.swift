import AppKit
import ClearCommandTabCore

@MainActor
struct SwitcherItem {
    let id: SwitcherTargetID
    let name: String
    let icon: CGImage?
    var badge: String? = nil
    var windowTitle: String? = nil
}

@MainActor
final class SwitcherPanel: NSPanel {
    var onSelect: ((SwitcherTargetID, Bool) -> Void)?
    private var surface: NSView
    private var glassProfile = GlassProfile.selected
    private let canvas = NSView()
    private let scroll = NSScrollView()
    private let row = NSView()
    private let selectionHighlight = NSVisualEffectView()
    private let nameLabel = NSTextField(labelWithString: "")
    private var cells: [SwitcherTargetID: ApplicationCell] = [:]
    private var displayedIDs: [SwitcherTargetID] = []
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
        surface = NSView()
        super.init(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered, defer: false)
        title = "ClearCommandTab"
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
        surface = glassProfile.makeSurface(content: canvas)
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
        setAccessibilityLabel("ClearCommandTab application switcher")
    }

    func applyGlassProfile(_ profile: GlassProfile) {
        guard profile != glassProfile else { return }
        glassProfile = profile
        // Recreate a plain view for Current; no private reset value is guessed.
        canvas.removeFromSuperview()
        surface = profile.makeSurface(content: canvas)
        contentView = surface
    }

    func display(items: [SwitcherItem], selected: SwitcherTargetID?, screen: NSScreen) {
        if !isVisible {
            pointer.reset(at: NSEvent.mouseLocation)
        }
        let showsTitles = items.contains { $0.windowTitle != nil }
        guard let newLayout = SwitcherLayout(applicationCount: items.count, availableSize: screen.visibleFrame.size,
                                            showsTitles: showsTitles) else {
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
                              width: newLayout.viewportWidth, height: newLayout.rowHeight)
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
        row.frame = NSRect(x: 0, y: 0, width: newLayout.documentWidth, height: newLayout.rowHeight)
        for (index, id) in ids.enumerated() {
            guard let cell = cells[id] else { continue }
            cell.item = items[index]
            cell.titleBandHeight = newLayout.titleBandHeight
            cell.titleFontSize = newLayout.labelFontSize
            cell.frame = newLayout.tileFrame(at: index)
            cell.isSelected = id == selected
            cell.layoutTitle()
        }
        selectedIndex = selected.flatMap { ids.firstIndex(of: $0) }
        if let selected, let cell = cells[selected] {
            let inset = max(1, newLayout.tileSize / 144)
            selectionHighlight.frame = NSRect(x: cell.frame.minX + inset, y: newLayout.titleBandHeight + inset,
                                               width: newLayout.tileSize - inset * 2, height: newLayout.tileSize - inset * 2)
            selectionHighlight.layer?.cornerRadius = newLayout.tileSize * 0.27
            selectionHighlight.isHidden = false
        } else { selectionHighlight.isHidden = true }
        nameLabel.font = .systemFont(ofSize: newLayout.labelFontSize, weight: .semibold)
        nameLabel.stringValue = selected.flatMap { id in items.first { $0.id == id }?.name } ?? ""
        if let selected, let cell = cells[selected] { row.scrollToVisible(cell.frame) }
        positionCaption()
        if showsTitles { nameLabel.isHidden = true }
        if !isKeyWindow { makeKeyAndOrderFront(nil) }
        else { orderFrontRegardless() }
    }

    private func positionCaption() {
        guard let layout, layout.titleBandHeight == 0, let selectedIndex else { nameLabel.isHidden = true; return }
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
    var onSelect: ((SwitcherTargetID, Bool) -> Void)?
    var onMotion: ((SwitcherTargetID, NSPoint) -> Void)?
    var isSelected = false {
        didSet {
            if isSelected != oldValue {
                needsDisplay = true
                updateAccessibility()
            }
        }
    }
    var titleBandHeight: CGFloat = 0
    var titleFontSize: CGFloat = 13
    private let titleLabel = PassiveTitleLabel(labelWithString: "")
    private var tracking: NSTrackingArea?

    init(item: SwitcherItem) {
        self.item = item
        super.init(frame: .zero)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        titleLabel.alignment = .center
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.maximumNumberOfLines = 2
        titleLabel.cell?.wraps = true
        titleLabel.cell?.isScrollable = false
        titleLabel.setAccessibilityElement(false)
        addSubview(titleLabel)
        updateAccessibility()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    private func updateAccessibility() {
        setAccessibilityLabel([item.name, item.windowTitle].compactMap { $0 }.joined(separator: ": "))
        setAccessibilityValue([isSelected ? "Selected" : nil,
                               item.badge.map { "Badge: \($0)" }].compactMap { $0 }.joined(separator: ", "))
    }

    func layoutTitle() {
        titleLabel.isHidden = item.windowTitle == nil
        titleLabel.stringValue = item.windowTitle ?? ""
        titleLabel.font = .systemFont(ofSize: titleFontSize, weight: isSelected ? .semibold : .regular)
        titleLabel.frame = NSRect(x: 0, y: 0, width: bounds.width, height: max(0, titleBandHeight - 4))
        toolTip = [item.name, item.windowTitle].compactMap { $0 }.joined(separator: " — ")
    }

    override func draw(_ dirtyRect: NSRect) {
        // App icons already include their optical margin; draw the full canvas.
        let iconRect = NSRect(x: 0, y: titleBandHeight, width: bounds.width, height: bounds.width)
        if let icon = item.icon ?? ApplicationIcon.fallback, let context = NSGraphicsContext.current?.cgContext {
            context.saveGState()
            context.interpolationQuality = .high
            context.draw(icon, in: iconRect)
            context.restoreGState()
        }
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
                              y: min(iconRect.minY + iconRect.height * 0.86 - height / 2, iconRect.maxY - height - edge),
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

@MainActor
private final class PassiveTitleLabel: NSTextField {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
