import AppKit
import ServiceManagement

/// Follow the window's effective appearance, including changes while About is open.
final class AppearanceIconView: NSImageView {
    private let lightImage: NSImage
    private let darkImage: NSImage?

    init(light: NSImage, dark: NSImage?) {
        lightImage = light
        darkImage = dark
        super.init(frame: .zero)
        imageScaling = .scaleProportionallyUpOrDown
        updateImage()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateImage()
    }

    private func updateImage() {
        let isDark = effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        image = isDark ? darkImage ?? lightImage : lightImage
    }
}

private final class SettingsDocumentView: NSView {
    override var isFlipped: Bool { true }
}

/// The document has its natural height; only the viewport is screen-limited.
private final class SettingsPage: NSScrollView {
    let stack = NSStackView()
    private let document = SettingsDocumentView()
    private var stackWidth: NSLayoutConstraint!

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 560, height: 1))
        drawsBackground = false
        borderType = .noBorder
        hasVerticalScroller = true
        autohidesScrollers = true
        scrollerStyle = .overlay
        documentView = document
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(stack)
        stackWidth = stack.widthAnchor.constraint(equalToConstant: 512)
        NSLayoutConstraint.activate([
            stackWidth,
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 24),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 24),
        ])
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func measure(width: CGFloat) -> CGFloat {
        stackWidth.constant = max(1, width - 48)
        document.setFrameSize(NSSize(width: width, height: max(1, document.frame.height)))
        document.layoutSubtreeIfNeeded()
        let height = ceil(stack.fittingSize.height) + 48
        document.setFrameSize(NSSize(width: width, height: height))
        document.layoutSubtreeIfNeeded()
        return height
    }
}

private final class SettingsTabs: NSTabViewController {
    var onSelection: (() -> Void)?
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        onSelection?()
    }
}

enum SettingsWindowFrame {
    static func fitting(_ current: NSRect, documentHeight: CGFloat,
                        chromeHeight: CGFloat, visibleFrame: NSRect) -> NSRect {
        let height = min(visibleFrame.height, max(1, ceil(documentHeight + chromeHeight)))
        let x = max(visibleFrame.minX, min(current.minX, visibleFrame.maxX - current.width))
        let y = max(visibleFrame.minY, min(current.maxY - height, visibleFrame.maxY - height))
        return NSRect(x: x, y: y, width: current.width, height: height)
    }
}

@MainActor
final class SettingsAppWindow: NSWindow {
    var onQuit: () -> Void = { NSApp.terminate(nil) }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection([.command, .option, .shift, .control])
        if event.type == .keyDown, modifiers == .command,
           event.charactersIgnoringModifiers?.lowercased() == "q" {
            onQuit()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

@MainActor
final class SettingsWindow: NSWindowController, NSWindowDelegate {
    var onShowIcon: ((Bool) -> Void)?
    var onTogglePause: (() -> Void)?
    var onCheckPermission: (() -> Void)?
    var onGlassProfile: ((GlassProfile) -> Void)?
    var onYellowButton: ((Bool) -> Void)?
    var onClose: (() -> Void)?
    private let tabs = SettingsTabs()
    private var resizing = false
    private let glassChoice = NSPopUpButton()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let detailLabel = NSTextField(wrappingLabelWithString: "")
    private let yellowStatusLabel = NSTextField(wrappingLabelWithString: "")
    private let permissionLabel = NSTextField(labelWithString: "Not checked")
    private let permissionSymbol = NSImageView()
    private let grantButton = NSButton(title: "Grant permission…", target: nil, action: nil)
    private let bundleInfo: [String: Any]
    private let aboutIcon: AppearanceIconView
    private let showIcon = NSButton(checkboxWithTitle: "Show menu bar icon", target: nil, action: nil)
    private let launchAtLogin = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let pauseButton = NSButton(title: "Pause", target: nil, action: nil)
    private let yellowButton = NSButton(checkboxWithTitle: "Yellow button hides app", target: nil, action: nil)

    init(info: [String: Any] = Bundle.main.infoDictionary ?? [:], darkIcon: NSImage? = nil) {
        bundleInfo = info
        let bundledDarkIcon = Bundle.main.url(forResource: "ClearCommandTab-dark", withExtension: "icns")
            .flatMap { NSImage(contentsOf: $0) }
        aboutIcon = AppearanceIconView(light: NSApp.applicationIconImage, dark: darkIcon ?? bundledDarkIcon)
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = []
        let window = SettingsAppWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 300),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "ClearCommandTab Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        window.delegate = self
        addTab(to: tabs, title: "Settings", symbol: "gearshape", content: settingsPage())
        addTab(to: tabs, title: "Guide", symbol: "questionmark.circle", content: guidePage())
        addTab(to: tabs, title: "About", symbol: "info.circle", content: aboutPage())
        window.contentViewController = tabs
        tabs.onSelection = { [weak self] in self?.fitSelectedPage(animate: true) }
        fitSelectedPage()
        window.center()
    }

    /// Drawn locally at logical size; this image is decorative, not a window control.
    private static func yellowButtonImage() -> NSImage {
        NSImage(size: NSSize(width: 16, height: 16), flipped: false) { _ in
            let circle = NSBezierPath(ovalIn: NSRect(x: 2, y: 2, width: 12, height: 12))
            NSColor(calibratedRed: 1, green: 0.75, blue: 0.18, alpha: 1).setFill()
            circle.fill()
            NSColor(calibratedRed: 0.72, green: 0.49, blue: 0.08, alpha: 1).setStroke()
            circle.lineWidth = 0.6
            circle.stroke()
            let minus = NSBezierPath()
            minus.move(to: NSPoint(x: 5, y: 8))
            minus.line(to: NSPoint(x: 11, y: 8))
            minus.lineWidth = 1
            minus.stroke()
            return true
        }
    }

    override func showWindow(_ sender: Any?) {
        fitSelectedPage()
        super.showWindow(sender)
    }

    func windowWillClose(_ notification: Notification) { onClose?() }

    func fitSelectedPage(animate: Bool = false, visibleFrame: NSRect? = nil) {
        guard !resizing, let window,
              tabs.tabViewItems.indices.contains(tabs.selectedTabViewItemIndex),
              let page = tabs.tabViewItems[tabs.selectedTabViewItemIndex].viewController?.view as? SettingsPage,
              let screenFrame = visibleFrame ?? window.screen?.visibleFrame ?? NSScreen.main?.visibleFrame else { return }
        resizing = true
        defer { resizing = false }
        let previousFrame = window.frame
        // NSTabViewController can initially substitute its default 500-point width.
        // Establish the requested content width before measuring wrapped text.
        if let content = window.contentView, abs(content.frame.width - 560) > 0.5 {
            window.setContentSize(NSSize(width: 560, height: content.frame.height))
        }
        window.contentView?.layoutSubtreeIfNeeded()
        let height = page.measure(width: 560)
        let chrome = max(0, window.frame.height - page.frame.height)
        let anchoredFrame = NSRect(origin: previousFrame.origin,
                                  size: NSSize(width: window.frame.width, height: previousFrame.height))
        let frame = SettingsWindowFrame.fitting(anchoredFrame, documentHeight: height,
                                               chromeHeight: chrome, visibleFrame: screenFrame)
        if abs(frame.height - window.frame.height) > 0.5 || frame.origin != window.frame.origin {
            window.setFrame(frame, display: window.isVisible,
                            animate: animate && window.isVisible && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        }
        window.contentView?.layoutSubtreeIfNeeded()
    }

    private func addTab(to tabs: NSTabViewController, title: String, symbol: String, content: NSView) {
        let controller = NSViewController()
        controller.title = title
        controller.view = content
        let item = NSTabViewItem(viewController: controller)
        item.label = title
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
        tabs.addTabViewItem(item)
    }

    private func page() -> (NSView, NSStackView) {
        let page = SettingsPage()
        return (page, page.stack)
    }

    private func section(_ title: String, in stack: NSStackView) {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        stack.addArrangedSubview(label)
    }

    private func explanation(_ text: String, in stack: NSStackView) {
        let label = NSTextField(wrappingLabelWithString: text)
        label.font = .systemFont(ofSize: 12)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentCompressionResistancePriority(.required, for: .vertical)
        stack.addArrangedSubview(label)
        label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        stack.setCustomSpacing(18, after: label)
    }

    private func settingsPage() -> NSView {
        let (view, stack) = page()
        section("Appearance", in: stack)
        let glassRow = NSStackView()
        glassRow.spacing = 12
        glassRow.addArrangedSubview(NSTextField(labelWithString: "Glass effect:"))
        glassChoice.identifier = NSUserInterfaceItemIdentifier("glassChoice")
        glassChoice.addItems(withTitles: GlassProfile.allCases.map(\.title))
        glassChoice.target = self
        glassChoice.action = #selector(glassChanged)
        glassRow.addArrangedSubview(glassChoice)
        stack.addArrangedSubview(glassRow)
        explanation(GlassProfile.altTabAvailable
            ? "Choose a glass finish or an opaque Matte background."
            : "Glass finishes use the same fallback on this Mac. Matte is opaque.", in: stack)

        section("Startup & menu bar", in: stack)
        launchAtLogin.target = self
        launchAtLogin.action = #selector(loginChanged)
        stack.addArrangedSubview(launchAtLogin)
        showIcon.target = self
        showIcon.action = #selector(iconChanged)
        if #available(macOS 26.0, *) {
            let visibilityRow = NSStackView()
            visibilityRow.spacing = 12
            visibilityRow.addArrangedSubview(showIcon)
            visibilityRow.addArrangedSubview(NSButton(title: "Menu Bar Settings…", target: self, action: #selector(openMenuBarSettings)))
            stack.addArrangedSubview(visibilityRow)
            explanation("Icon missing? Enable ClearCommandTab in System Settings → Menu Bar → Allow in the Menu Bar.", in: stack)
        } else {
            stack.addArrangedSubview(showIcon)
            explanation("If you hide the icon, reopen ClearCommandTab from Applications or Spotlight and turn this option on.", in: stack)
        }

        section("Window behavior", in: stack)
        yellowButton.target = self
        yellowButton.action = #selector(yellowButtonChanged)
        let yellowRow = NSStackView()
        yellowRow.alignment = .centerY
        yellowRow.spacing = 6
        let yellowIcon = NSImageView(image: Self.yellowButtonImage())
        yellowIcon.identifier = NSUserInterfaceItemIdentifier("yellowButtonIllustration")
        yellowIcon.setAccessibilityElement(false)
        yellowRow.addArrangedSubview(yellowButton)
        yellowRow.addArrangedSubview(yellowIcon)
        yellowRow.translatesAutoresizingMaskIntoConstraints = false
        yellowIcon.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(yellowRow)
        NSLayoutConstraint.activate([
            yellowIcon.widthAnchor.constraint(equalToConstant: 16),
            yellowIcon.heightAnchor.constraint(equalToConstant: 16),
        ])
        explanation("Click the yellow minimize button to hide the entire app. Modified clicks keep macOS behavior.", in: stack)

        section("Status & permissions", in: stack)
        let accessibilityRow = NSStackView()
        accessibilityRow.alignment = .centerY
        accessibilityRow.spacing = 8
        accessibilityRow.addArrangedSubview(NSTextField(labelWithString: "Accessibility:"))
        permissionSymbol.setAccessibilityElement(false)
        permissionSymbol.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            permissionSymbol.widthAnchor.constraint(equalToConstant: 14),
            permissionSymbol.heightAnchor.constraint(equalToConstant: 14),
        ])
        accessibilityRow.addArrangedSubview(permissionSymbol)
        permissionLabel.identifier = NSUserInterfaceItemIdentifier("accessibilityStatus")
        permissionLabel.font = .systemFont(ofSize: 13, weight: .medium)
        accessibilityRow.addArrangedSubview(permissionLabel)
        stack.addArrangedSubview(accessibilityRow)
        let permissionRow = NSStackView()
        permissionRow.spacing = 8
        let checkButton = NSButton(title: "Check permission", target: self, action: #selector(checkPermission))
        checkButton.identifier = NSUserInterfaceItemIdentifier("checkPermission")
        permissionRow.addArrangedSubview(checkButton)
        grantButton.identifier = NSUserInterfaceItemIdentifier("grantPermission")
        grantButton.target = self
        grantButton.action = #selector(grantPermission)
        grantButton.isHidden = true
        permissionRow.addArrangedSubview(grantButton)
        stack.addArrangedSubview(permissionRow)
        explanation("Required for shortcuts and yellow-button hiding. No Screen Recording access needed.", in: stack)

        let switchingRow = NSStackView()
        switchingRow.alignment = .centerY
        switchingRow.spacing = 12
        statusLabel.identifier = NSUserInterfaceItemIdentifier("switchingStatus")
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        switchingRow.addArrangedSubview(statusLabel)
        pauseButton.target = self
        pauseButton.action = #selector(togglePause)
        switchingRow.addArrangedSubview(pauseButton)
        stack.addArrangedSubview(switchingRow)
        for (label, identifier) in [(detailLabel, "switchingDetail"), (yellowStatusLabel, "yellowButtonStatus")] {
            label.identifier = NSUserInterfaceItemIdentifier(identifier)
            label.font = .systemFont(ofSize: 12)
            label.textColor = .secondaryLabelColor
            label.translatesAutoresizingMaskIntoConstraints = false
            label.setContentCompressionResistancePriority(.required, for: .vertical)
            label.isHidden = true
            stack.addArrangedSubview(label)
            label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        updateStatus(SettingsStatus(permissionChecked: false, accessibilityGranted: false,
                                    keyboardRunning: false, paused: false))
        return view
    }

    private func guidePage() -> NSView {
        let (view, stack) = page()
        section("Two ways to switch", in: stack)
        for (keys, title, detail) in [
            ("⌘Tab", "Visible apps", "Skips apps hidden with Hide or ⌘H."),
            ("⌘⌥Tab", "Hidden apps", "Reveals the selected app and gives it keyboard focus."),
        ] {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .top
            row.spacing = 16
            row.translatesAutoresizingMaskIntoConstraints = false
            let shortcut = NSTextField(labelWithString: keys)
            shortcut.font = .monospacedSystemFont(ofSize: 14, weight: .medium)
            shortcut.widthAnchor.constraint(equalToConstant: 80).isActive = true
            row.addArrangedSubview(shortcut)
            let description = NSStackView()
            description.orientation = .vertical
            description.alignment = .leading
            description.spacing = 3
            let heading = NSTextField(labelWithString: title)
            heading.font = .systemFont(ofSize: 13, weight: .medium)
            let body = NSTextField(wrappingLabelWithString: detail)
            body.font = .systemFont(ofSize: 12)
            body.textColor = .secondaryLabelColor
            body.translatesAutoresizingMaskIntoConstraints = false
            description.addArrangedSubview(heading)
            description.addArrangedSubview(body)
            body.widthAnchor.constraint(equalTo: description.widthAnchor).isActive = true
            row.addArrangedSubview(description)
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            stack.setCustomSpacing(16, after: row)
        }
        section("Quick switches stay invisible", in: stack)
        explanation("Release within 150 ms to switch without a panel. Keep holding to show it, or press Tab again to show it immediately.", in: stack)
        section("While choosing", in: stack)
        explanation("Hold Shift to move backward, use ← / →, or press Escape to cancel. Release Command to confirm. Move the pointer to select an icon, or click to confirm.", in: stack)
        section("Menu shortcuts", in: stack)
        explanation("Right-click the menu bar icon for Settings (⌘,) or Quit (⌘Q). Left-click to pause or resume. Pausing suspends shortcuts and yellow-button hiding.", in: stack)
        return view
    }

    private func aboutPage() -> NSView {
        let (view, stack) = page()
        stack.alignment = .centerX
        stack.spacing = 12
        let icon = aboutIcon
        icon.identifier = NSUserInterfaceItemIdentifier("aboutIcon")
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 88),
            icon.heightAnchor.constraint(equalToConstant: 88),
        ])
        stack.addArrangedSubview(icon)
        let title = NSTextField(labelWithString: "ClearCommandTab")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        stack.addArrangedSubview(title)
        let info = bundleInfo
        let version = info["CFBundleShortVersionString"] as? String ?? "Development"
        let build = info["CFBundleVersion"] as? String
        let versionLabel = NSTextField(labelWithString: "Version \(version)")
        versionLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(versionLabel)
        if let build {
            let buildLabel = NSTextField(labelWithString: "Build \(build)")
            buildLabel.font = .systemFont(ofSize: 11)
            buildLabel.textColor = .secondaryLabelColor
            buildLabel.toolTip = "Identifies this particular build of the app."
            stack.addArrangedSubview(buildLabel)
            stack.setCustomSpacing(24, after: buildLabel)
        } else { stack.setCustomSpacing(24, after: versionLabel) }
        let description = NSTextField(labelWithString: "Native app for macos, enables better window switching appearance.")
        stack.addArrangedSubview(description)
        let authorText = NSMutableAttributedString(string: "Author : CorbeusUltra", attributes: [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: NSColor.secondaryLabelColor,
        ])
        let authorURL = URL(string: "https://github.com/CorbeusUltra")!
        authorText.addAttributes([
            .link: authorURL,
            .foregroundColor: NSColor.linkColor,
            .underlineStyle: NSUnderlineStyle.single.rawValue,
        ], range: (authorText.string as NSString).range(of: "CorbeusUltra"))
        let author = NSTextField(labelWithAttributedString: authorText)
        author.isSelectable = true
        author.allowsEditingTextAttributes = true
        author.toolTip = authorURL.absoluteString
        stack.addArrangedSubview(author)
        stack.setCustomSpacing(24, after: author)
        if repositoryURL != nil {
            let repository = NSButton(title: "GitHub repository ↗", target: self, action: #selector(openRepository))
            repository.identifier = NSUserInterfaceItemIdentifier("repositoryLink")
            repository.bezelStyle = .inline
            repository.toolTip = repositoryURL?.absoluteString
            stack.addArrangedSubview(repository)
        } else {
            let placeholder = NSTextField(labelWithString: "GitHub repository — Coming soon")
            placeholder.identifier = NSUserInterfaceItemIdentifier("repositoryPlaceholder")
            placeholder.textColor = .secondaryLabelColor
            stack.addArrangedSubview(placeholder)
        }
        let privacy = NSTextField(labelWithString: "Runs locally. No accounts or analytics.")
        privacy.font = .systemFont(ofSize: 12)
        privacy.textColor = .secondaryLabelColor
        stack.addArrangedSubview(privacy)
        return view
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(status: SettingsStatus, iconVisible: Bool, glassProfile: GlassProfile,
                yellowButtonHidesApp: Bool) {
        updateStatus(status)
        glassChoice.selectItem(at: GlassProfile.allCases.firstIndex(of: glassProfile) ?? 0)
        pauseButton.title = status.switching == .paused ? "Resume" : "Pause"
        showIcon.state = iconVisible ? .on : .off
        yellowButton.state = yellowButtonHidesApp ? .on : .off
        let loginStatus = SMAppService.mainApp.status
        launchAtLogin.state = (loginStatus == .enabled || loginStatus == .requiresApproval) ? .on : .off
        if window?.isVisible == true { fitSelectedPage() }
    }

    private func updateStatus(_ status: SettingsStatus) {
        let color: NSColor
        switch status.accessibility {
        case .notChecked: color = .secondaryLabelColor
        case .granted: color = .systemGreen
        case .notGranted: color = .systemRed
        }
        permissionLabel.stringValue = status.accessibility.title
        permissionLabel.textColor = color
        permissionLabel.setAccessibilityValue(status.accessibility.title)
        permissionSymbol.image = NSImage(systemSymbolName: status.accessibility.symbol, accessibilityDescription: nil)
        permissionSymbol.contentTintColor = color
        grantButton.isHidden = !status.showsGrantPermission
        statusLabel.stringValue = status.switching.title
        statusLabel.textColor = status.switching == .active ? .systemGreen
            : status.switching == .unavailable ? .systemRed : .secondaryLabelColor
        detailLabel.stringValue = status.detail ?? ""
        detailLabel.isHidden = status.detail == nil
        yellowStatusLabel.stringValue = status.yellowButtonFailure.map { "Yellow button: \($0)" } ?? ""
        yellowStatusLabel.textColor = .systemOrange
        yellowStatusLabel.isHidden = status.yellowButtonFailure == nil
    }

    private var repositoryURL: URL? {
        guard let value = bundleInfo["GitHubRepositoryURL"] as? String,
              let url = URL(string: value), url.scheme == "https", url.host != nil else { return nil }
        return url
    }

    @objc private func openRepository() {
        if let url = repositoryURL { NSWorkspace.shared.open(url) }
    }

    @objc private func glassChanged() {
        guard GlassProfile.allCases.indices.contains(glassChoice.indexOfSelectedItem) else { return }
        onGlassProfile?(GlassProfile.allCases[glassChoice.indexOfSelectedItem])
    }
    @objc private func iconChanged() { onShowIcon?(showIcon.state == .on) }
    @objc private func yellowButtonChanged() { onYellowButton?(yellowButton.state == .on) }
    @objc private func togglePause() { onTogglePause?() }
    @objc private func checkPermission() { onCheckPermission?() }

    @objc private func openMenuBarSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.ControlCenter-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func grantPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func loginChanged() {
        do {
            if launchAtLogin.state == .on { try SMAppService.mainApp.register() }
            else { try SMAppService.mainApp.unregister() }
            if SMAppService.mainApp.status == .requiresApproval {
                SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            let alert = NSAlert()
            alert.messageText = "Could not change Launch at login"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
        let loginStatus = SMAppService.mainApp.status
        launchAtLogin.state = (loginStatus == .enabled || loginStatus == .requiresApproval) ? .on : .off
    }
}
