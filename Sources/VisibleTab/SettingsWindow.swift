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
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 580),
                              styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.title = "VisibleTab Settings"
        window.isReleasedWhenClosed = false
        super.init(window: window)
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false
        window.contentView?.addSubview(stack)
        if let content = window.contentView {
            NSLayoutConstraint.activate([
                stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
                stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
                stack.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            ])
        }
        let title = NSTextField(labelWithString: "VisibleTab")
        title.font = .systemFont(ofSize: 17, weight: .semibold)
        stack.addArrangedSubview(title)
        let description = NSTextField(wrappingLabelWithString:
            "⌘Tab: visible apps. ⌘⌥Tab: hidden apps. ⌥Tab: windows on the current Space, excluding minimized windows. Hold Shift to cycle backward.")
        description.font = .systemFont(ofSize: 12)
        description.textColor = .secondaryLabelColor
        stack.addArrangedSubview(description)
        statusLabel.font = .systemFont(ofSize: 12, weight: .medium)
        stack.addArrangedSubview(statusLabel)
        let permissionRow = NSStackView()
        permissionRow.spacing = 8
        let grant = NSButton(title: "Grant Accessibility…", target: self, action: #selector(grantPermission))
        let check = NSButton(title: "Check permission", target: self, action: #selector(checkPermission))
        permissionRow.addArrangedSubview(grant)
        permissionRow.addArrangedSubview(check)
        stack.addArrangedSubview(permissionRow)
        showIcon.target = self
        showIcon.action = #selector(iconChanged)
        stack.addArrangedSubview(showIcon)
        let iconHelp = NSTextField(wrappingLabelWithString:
            "If you hide the icon, reopen VisibleTab from Applications or Spotlight to access these controls.")
        iconHelp.font = .systemFont(ofSize: 11)
        iconHelp.textColor = .secondaryLabelColor
        stack.addArrangedSubview(iconHelp)
        let glassRow = NSStackView()
        glassRow.spacing = 8
        glassRow.addArrangedSubview(NSTextField(labelWithString: "Glass:"))
        glassChoice.addItems(withTitles: ["Current", "AltTab"])
        glassChoice.target = self
        glassChoice.action = #selector(glassChanged)
        glassRow.addArrangedSubview(glassChoice)
        stack.addArrangedSubview(glassRow)
        let glassHelp = NSTextField(wrappingLabelWithString: GlassProfile.altTabAvailable
            ? "Current restores the previous public clear material. AltTab tries a stronger native clear-glass profile."
            : "The AltTab glass profile is unavailable on this macOS. Both choices use the current material.")
        glassHelp.font = .systemFont(ofSize: 11)
        glassHelp.textColor = .secondaryLabelColor
        stack.addArrangedSubview(glassHelp)
        launchAtLogin.target = self
        launchAtLogin.action = #selector(loginChanged)
        stack.addArrangedSubview(launchAtLogin)
        let controls = NSStackView()
        controls.spacing = 8
        pauseButton.target = self
        pauseButton.action = #selector(togglePause)
        controls.addArrangedSubview(pauseButton)
        controls.addArrangedSubview(NSButton(title: "Quit", target: NSApp, action: #selector(NSApplication.terminate(_:))))
        stack.addArrangedSubview(controls)
        for label in [description, statusLabel, iconHelp, glassHelp] {
            label.translatesAutoresizingMaskIntoConstraints = false
            label.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        window.center()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    func update(status: String, paused: Bool, iconVisible: Bool, glassProfile: GlassProfile) {
        statusLabel.stringValue = status
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
