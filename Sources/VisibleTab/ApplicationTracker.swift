import AppKit
import VisibleTabCore

@MainActor
final class ApplicationTracker {
    private(set) var history: ApplicationHistory
    private(set) var applications: [Int32: NSRunningApplication] = [:]
    private(set) var icons: [Int32: CGImage] = [:]
    var onChange: ((Bool) -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var saveWork: DispatchWorkItem?
    private var iconRetries: [Int32: DispatchWorkItem] = [:]
    private var retriedIcons: Set<Int32> = []
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
                        self.refreshIcon(app.processIdentifier)
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
        for pid in Array(iconRetries.keys) where applications[pid] == nil {
            iconRetries.removeValue(forKey: pid)?.cancel()
        }
        icons = icons.filter { applications[$0.key] != nil }
        retriedIcons.formIntersection(applications.keys)
        for app in running where icons[app.processIdentifier] == nil && iconRetries[app.processIdentifier] == nil {
            refreshIcon(app.processIdentifier)
            if retriedIcons.insert(app.processIdentifier).inserted {
                retryLaunchIcon(app.processIdentifier, attempt: 0)
            }
        }
        history.update(running.map {
            ApplicationRecord(id: $0.processIdentifier,
                              persistenceID: $0.bundleIdentifier ?? $0.bundleURL?.path ?? "pid:\($0.processIdentifier)",
                              name: $0.localizedName ?? "Application",
                              isHidden: $0.isHidden)
        })
    }

    func refreshIcons() {
        for pid in applications.keys { refreshIcon(pid) }
    }

    private func refreshIcon(_ pid: Int32) {
        guard applications[pid] != nil, let app = NSRunningApplication(processIdentifier: pid), !app.isTerminated else { return }
        let scale = NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
        if let image = ApplicationIcon.resolve(app, pixels: min(512, max(256, Int(144 * scale)))) {
            icons[pid] = image
        }
    }

    private func retryLaunchIcon(_ pid: Int32, attempt: Int) {
        let delays: [Double] = [0.2, 0.6, 1.5, 3]
        guard attempt < delays.count else { iconRetries[pid] = nil; return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.applications[pid] != nil else { return }
            self.refreshIcon(pid)
            self.onChange?(false)
            self.retryLaunchIcon(pid, attempt: attempt + 1)
        }
        iconRetries[pid]?.cancel()
        iconRetries[pid] = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delays[attempt], execute: work)
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
