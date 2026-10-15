import AppKit
import VisibleTabCore

@MainActor
final class ApplicationTracker {
    private(set) var history: ApplicationHistory
    private(set) var applications: [Int32: NSRunningApplication] = [:]
    private(set) var icons: [Int32: NSImage] = [:]
    var onChange: ((Bool) -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var saveWork: DispatchWorkItem?
    private let defaults: UserDefaults
    private let workspace = NSWorkspace.shared

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        history = ApplicationHistory(excludedID: ProcessInfo.processInfo.processIdentifier,
                                     rememberedOrder: defaults.stringArray(forKey: "applicationOrder") ?? [])
        refresh()
        if let front = workspace.frontmostApplication { history.activate(front.processIdentifier) }
        let center = workspace.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.refresh()
                    let activated = name == NSWorkspace.didActivateApplicationNotification
                    if activated, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication {
                        self.history.activate(app.processIdentifier)
                        self.scheduleSave()
                    }
                    self.onChange?(activated)
                }
            })
        }
    }

    func refresh() {
        let ownBundle = Bundle.main.bundleIdentifier
        let running = workspace.runningApplications.filter {
            !$0.isTerminated && $0.activationPolicy == .regular &&
            $0.processIdentifier > 0 && (ownBundle == nil || $0.bundleIdentifier != ownBundle)
        }
        applications = Dictionary(running.map { ($0.processIdentifier, $0) }, uniquingKeysWith: { first, _ in first })
        icons = icons.filter { applications[$0.key] != nil }
        for app in running where icons[app.processIdentifier] == nil {
            if let icon = app.icon { icons[app.processIdentifier] = icon }
        }
        history.update(running.map {
            ApplicationRecord(id: $0.processIdentifier,
                              persistenceID: $0.bundleIdentifier ?? $0.bundleURL?.path ?? "pid:\($0.processIdentifier)",
                              name: $0.localizedName ?? "Application",
                              isHidden: $0.isHidden)
        })
    }

    func save() {
        saveWork?.cancel()
        defaults.set(history.rememberedOrder, forKey: "applicationOrder")
    }

    private func scheduleSave() {
        saveWork?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.save() }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
    }
}
