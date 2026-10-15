import AppKit
import ServiceManagement

@MainActor
final class SettingsWindow: NSWindowController {
    var onShowIcon: ((Bool) -> Void)?
    var onTogglePause: (() -> Void)?
    var onCheckPermission: (() -> Void)?
    var onGlassProfile: ((GlassProfile) -> Void)?
    private let glassChoice = NSPopUpButton()
    private let statusLabel = NSTextField(wrappingLabelWithString: "")
    private let showIcon = NSButton(checkboxWithTitle: "Show menu bar icon", target: nil, action: nil)
    private let launchAtLogin = NSButton(checkboxWithTitle: "Launch at login", target: nil, action: nil)
    private let pauseButton = NSButton(title: "Pause", target: nil, action: nil)

    init() {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        tabs.transitionOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 560, height: 500),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "ClearCommandTab Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        addTab(to: tabs, title: "Settings", symbol: "gearshape", content: settingsPage())
        addTab(to: tabs, title: "Guide", symbol: "questionmark.circle", content: guidePage())
        addTab(to: tabs, title: "About", symbol: "info.circle", content: aboutPage())
        window.contentViewController = tabs
        window.setContentSize(NSSize(width: 560, height: 500))
        window.center()
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
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 560, height: 500))
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: 24),
            stack.bottomAnchor.constraint(lessThanOrEqualTo: view.bottomAnchor, constant: -24),
        ])
        return (view, stack)
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
        glassChoice.addItems(withTitles: ["fully transparent", "original"])
        glassChoice.target = self
        glassChoice.action = #selector(glassChanged)
        glassRow.addArrangedSubview(glassChoice)
        stack.addArrangedSubview(glassRow)
        explanation(GlassProfile.altTabAvailable
            ? "fully transparent lets more of the background show through. original uses a stronger glass effect."
            : "original is unavailable on this Mac. Both choices use the same fallback appearance.", in: stack)

        section("Startup & menu bar", in: stack)
        launchAtLogin.target = self
        launchAtLogin.action = #selector(loginChanged)
        stack.addArrangedSubview(launchAtLogin)
        showIcon.target = self
        showIcon.action = #selector(iconChanged)
        stack.addArrangedSubview(showIcon)
        explanation("Click the menu bar icon to pause or resume; right-click to open its menu. If you hide the icon, reopen ClearCommandTab from Applications or Spotlight.", in: stack)

        section("Status & permissions", in: stack)
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        stack.addArrangedSubview(statusLabel)
        statusLabel.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        let permissionRow = NSStackView()
        permissionRow.spacing = 8
        permissionRow.addArrangedSubview(NSButton(title: "Grant Accessibility…", target: self, action: #selector(grantPermission)))
        permissionRow.addArrangedSubview(NSButton(title: "Check permission", target: self, action: #selector(checkPermission)))
        pauseButton.target = self
        pauseButton.action = #selector(togglePause)
        permissionRow.addArrangedSubview(pauseButton)
        stack.addArrangedSubview(permissionRow)
        explanation("Accessibility allows the keyboard shortcuts to work across apps. No Screen Recording permission is needed.", in: stack)
        return view
    }

    private func guidePage() -> NSView {
        let (view, stack) = page()
        section("Three ways to switch", in: stack)
        for (keys, title, detail) in [
            ("⌘Tab", "Visible apps", "Skips apps hidden with Hide or ⌘H."),
            ("⌘⌥Tab", "Hidden apps", "Reveals the selected app and gives it keyboard focus."),
            ("⌥Tab", "Windows", "Current Space only. Apps stay grouped; minimized windows are excluded."),
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
        explanation("Hold Shift to move backward, use ← / →, or press Escape to cancel. Release Command for apps or Option for windows to confirm. Move the pointer to select an icon, or click to confirm.", in: stack)
        section("Menu shortcuts", in: stack)
        explanation("Right-click the menu bar icon, then use ⌘, for Settings or ⌘Q to quit. A dimmed icon means switching is paused.", in: stack)
        return view
    }

    private func aboutPage() -> NSView {
        let (view, stack) = page()
        stack.alignment = .centerX
        stack.spacing = 12
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 88),
            icon.heightAnchor.constraint(equalToConstant: 88),
        ])
        stack.addArrangedSubview(icon)
        let title = NSTextField(labelWithString: "ClearCommandTab")
        title.font = .systemFont(ofSize: 22, weight: .semibold)
        stack.addArrangedSubview(title)
        let info = Bundle.main.infoDictionary ?? [:]
        let version = info["CFBundleShortVersionString"] as? String ?? "Development"
        let build = info["CFBundleVersion"] as? String
        let versionLabel = NSTextField(labelWithString: "Version \(version)" + (build.map { " (\($0))" } ?? ""))
        versionLabel.textColor = .secondaryLabelColor
        stack.addArrangedSubview(versionLabel)
        stack.setCustomSpacing(24, after: versionLabel)
        let description = NSTextField(labelWithString: "A native app and window switcher for macOS.")
        stack.addArrangedSubview(description)
        let author = NSTextField(labelWithString: "Created by Lucas Bourret")
        author.font = .systemFont(ofSize: 12)
        author.textColor = .secondaryLabelColor
        stack.addArrangedSubview(author)
        stack.setCustomSpacing(24, after: author)
        let privacy = NSTextField(labelWithString: "Runs locally. No accounts, analytics or network access.")
        privacy.font = .systemFont(ofSize: 12)
        privacy.textColor = .secondaryLabelColor
        stack.addArrangedSubview(privacy)
        return view
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(status: String, paused: Bool, iconVisible: Bool, glassProfile: GlassProfile) {
        let ready = "Ready. ⌘Tab: visible apps · ⌘⌥Tab: hidden apps · ⌥Tab: windows."
        statusLabel.stringValue = status == ready ? "Ready — keyboard shortcuts are active." : status
        glassChoice.selectItem(at: glassProfile == .current ? 0 : 1)
        pauseButton.title = paused ? "Resume" : "Pause"
        showIcon.state = iconVisible ? .on : .off
        let loginStatus = SMAppService.mainApp.status
        launchAtLogin.state = (loginStatus == .enabled || loginStatus == .requiresApproval) ? .on : .off
    }

    @objc private func glassChanged() { onGlassProfile?(glassChoice.indexOfSelectedItem == 0 ? .current : .altTab) }
    @objc private func iconChanged() { onShowIcon?(showIcon.state == .on) }
    @objc private func togglePause() { onTogglePause?() }
    @objc private func checkPermission() { onCheckPermission?() }

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
