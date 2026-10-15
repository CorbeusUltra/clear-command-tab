import AppKit
import VisibleTabCore

struct ApplicationPresentation {
    let name: String
    let bundleIdentifier: String?
}

@MainActor
final class ApplicationTracker {
    private(set) var history: ApplicationHistory
    private(set) var applications: [Int32: NSRunningApplication] = [:]
    private(set) var presentations: [Int32: ApplicationPresentation] = [:]
    private(set) var icons: [Int32: CGImage] = [:]
    private(set) var frontmostPID: Int32?
    private(set) var dockPID: Int32?
    var onChange: ((Bool) -> Void)?
    var onIconsChanged: (() -> Void)?
    private var records: [Int32: ApplicationRecord] = [:]
    private var observers: [NSObjectProtocol] = []
    private var saveWork: DispatchWorkItem?
    private var iconRetries: [Int32: DispatchWorkItem] = [:]
    private var retriedIcons: Set<Int32> = []
    private var iconInFlight: Set<Int32> = []
    private var deferredIcons: Set<Int32> = []
    private var lastIconRefresh: [Int32: TimeInterval] = [:]
    private let iconQueue = DispatchQueue(label: "local.lucas.VisibleTab.icons", qos: .utility)
    private let defaults: UserDefaults
    private let workspace = NSWorkspace.shared

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        history = ApplicationHistory(excludedID: ProcessInfo.processInfo.processIdentifier,
                                     rememberedOrder: defaults.stringArray(forKey: "applicationOrder") ?? [])
        iconQueue.async { _ = ApplicationIcon.fallback }
        refresh()
        frontmostPID = workspace.frontmostApplication?.processIdentifier
        if let frontmostPID { history.activate(frontmostPID) }
        let center = workspace.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                    let pid = app?.processIdentifier
                    let activated = name == NSWorkspace.didActivateApplicationNotification
                    if activated {
                        self.frontmostPID = pid
                        if let pid, self.applications[pid] == nil, app?.activationPolicy == .regular { self.refresh() }
                        if let pid {
                            self.history.activate(pid)
                            self.requestIcon(pid, force: false)
                            self.scheduleSave()
                        }
                    } else if let pid, let record = self.records[pid],
                              name == NSWorkspace.didHideApplicationNotification || name == NSWorkspace.didUnhideApplicationNotification {
                        // The notification supplies the new state; do not re-query every app.
                        self.records[pid] = ApplicationRecord(id: pid, persistenceID: record.persistenceID,
                                                             name: record.name,
                                                             isHidden: name == NSWorkspace.didHideApplicationNotification)
                        self.history.update(Array(self.records.values))
                    } else { self.refresh() }
                    self.onChange?(activated)
                }
            })
        }
    }

    var windowInputs: [WindowApplication] {
        records.values.map { .init(pid: $0.id, hidden: $0.isHidden) }
    }

    func recordConfirmedActivation(_ pid: Int32) {
        frontmostPID = pid
        history.activate(pid)
        scheduleSave()
    }

    func refresh() {
        dockPID = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first?.processIdentifier
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
        lastIconRefresh = lastIconRefresh.filter { applications[$0.key] != nil }
        presentations = presentations.filter { applications[$0.key] != nil }
        retriedIcons.formIntersection(applications.keys)
        records = Dictionary(running.map { app in
            let pid = app.processIdentifier
            let presentation = presentations[pid] ?? ApplicationPresentation(name: app.localizedName ?? "Application",
                                                                             bundleIdentifier: app.bundleIdentifier)
            presentations[pid] = presentation
            return (pid, ApplicationRecord(id: pid,
                                           persistenceID: presentation.bundleIdentifier ?? app.bundleURL?.path ?? "pid:\(pid)",
                                           name: presentation.name, isHidden: app.isHidden))
        }, uniquingKeysWith: { first, _ in first })
        history.update(Array(records.values))
        for pid in applications.keys where retriedIcons.insert(pid).inserted {
            requestIcon(pid, force: true)
            retryLaunchIcon(pid, attempt: 0)
        }
    }

    private func requestIcon(_ pid: Int32, force: Bool) {
        guard let app = applications[pid], !app.isTerminated else { return }
        let now = ProcessInfo.processInfo.systemUptime
        guard force || icons[pid] == nil || now - lastIconRefresh[pid, default: 0] >= 5 else { return }
        guard iconInFlight.insert(pid).inserted else {
            if force { deferredIcons.insert(pid) }
            return
        }
        lastIconRefresh[pid] = now
        let pixels = min(512, max(256, Int(144 * (NSScreen.screens.map(\.backingScaleFactor).max() ?? 2))))
        iconQueue.async { [weak self] in
            // NSRunningApplication is thread-safe; no image decoding runs on the UI loop.
            let image = autoreleasepool { ApplicationIcon.resolve(app, pixels: pixels) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.iconInFlight.remove(pid)
                if let current = self.applications[pid], current == app, !app.isTerminated, let image {
                    self.icons[pid] = image
                    self.onIconsChanged?()
                }
                if self.deferredIcons.remove(pid) != nil { self.requestIcon(pid, force: true) }
            }
        }
    }

    private func retryLaunchIcon(_ pid: Int32, attempt: Int) {
        let delays: [Double] = [0.2, 0.6, 1.5, 3]
        guard attempt < delays.count else { iconRetries[pid] = nil; return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.applications[pid] != nil else { return }
            self.requestIcon(pid, force: true)
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
