import AppKit
import Combine
import UserNotifications

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var statusItem: NSStatusItem!
    private var loginWindowController: LoginWindowController?
    private var refreshTimer: Timer?
    private var cancellables = Set<AnyCancellable>()

    private let service       = ClaudeAPIService.shared
    private let notifications = NotificationService.shared


    // MARK: - Refresh interval (persisted in UserDefaults)

    private var refreshInterval: TimeInterval {
        get {
            let stored = UserDefaults.standard.double(forKey: "refreshInterval")
            return stored > 0 ? stored : 120
        }
        set {
            UserDefaults.standard.set(newValue, forKey: "refreshInterval")
            restartTimer()
        }
    }

    // MARK: - Application lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        notifications.requestPermission()
        setupStatusItem()
        observeService()
        startApp()
    }

    // MARK: - Status bar

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.action = #selector(showMenu)
        button.target = self
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        updateIcon(data: nil)
    }

    private func updateIcon(data: UsageData?) {
        guard let button = statusItem.button else { return }

        let isStale = data?.isStale ?? false

        if let path = Bundle.main.path(forResource: "MenuBarIcon", ofType: "png"),
           let img = NSImage(contentsOfFile: path) {
            img.size = NSSize(width: 16, height: 16)
            button.image = img
        }

        if let label = data?.menuBarLabel, !label.isEmpty {
            button.title = isStale ? " ⚠ \(label)" : " \(label)"
        } else {
            button.title = ""
        }

        if let data = data {
            let staleNote = isStale ? " · stale" : ""
            button.toolTip = "Claude Usage Monitor · Updated \(data.lastUpdatedFormatted)\(staleNote)"
        } else {
            button.toolTip = "Claude Usage Monitor"
        }
    }

    // MARK: - Menu

    @objc private func showMenu() {
        guard let button = statusItem.button else { return }

        let menu = NSMenu()

        // Current usage info
        if let data = service.usageData {
            let pctStr = "\(Int(data.weeklyPercentage * 100))%"
            let usageItem = NSMenuItem(
                title: "Weekly: \(data.messagesUsed)/\(data.messagesLimit)  (\(pctStr))",
                action: nil,
                keyEquivalent: ""
            )
            usageItem.isEnabled = false
            menu.addItem(usageItem)

            if data.weeklyResetDate != nil {
                let resetItem = NSMenuItem(
                    title: "Resets in \(data.timeUntilReset)",
                    action: nil,
                    keyEquivalent: ""
                )
                resetItem.isEnabled = false
                menu.addItem(resetItem)
            }

            if data.isStale {
                let staleItem = NSMenuItem(title: "⚠  Data may be stale", action: nil, keyEquivalent: "")
                staleItem.isEnabled = false
                menu.addItem(staleItem)
            }
        } else {
            let noDataItem = NSMenuItem(title: "No data yet", action: nil, keyEquivalent: "")
            noDataItem.isEnabled = false
            menu.addItem(noDataItem)
        }

        menu.addItem(.separator())

        // Refresh interval submenu
        let intervalItem = NSMenuItem(title: "Refresh Interval", action: nil, keyEquivalent: "")
        let intervalMenu  = NSMenu()
        let options: [(String, TimeInterval)] = [
            ("30 seconds", 30),
            ("1 minute",   60),
            ("2 minutes",  120),
            ("5 minutes",  300),
            ("10 minutes", 600),
        ]
        for (label, interval) in options {
            let item = NSMenuItem(title: label, action: #selector(setRefreshInterval(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = interval
            item.state = abs(refreshInterval - interval) < 1 ? .on : .off
            intervalMenu.addItem(item)
        }
        intervalItem.submenu = intervalMenu
        menu.addItem(intervalItem)

        menu.addItem(.separator())

        let refreshItem = NSMenuItem(title: "Refresh Now", action: #selector(refreshNow), keyEquivalent: "r")
        refreshItem.target = self
        menu.addItem(refreshItem)

        menu.addItem(.separator())

        menu.addItem(NSMenuItem(
            title: "Quit",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        // Pop up below the status bar button
        let origin = NSPoint(x: 0, y: button.bounds.height + 4)
        menu.popUp(positioning: nil, at: origin, in: button)
    }

    @objc private func setRefreshInterval(_ sender: NSMenuItem) {
        guard let interval = sender.representedObject as? TimeInterval else { return }
        refreshInterval = interval
    }

    @objc private func refreshNow() {
        service.refresh()
    }

    // MARK: - Combine observers

    private func observeService() {
        service.$usageData
            .receive(on: DispatchQueue.main)
            .sink { [weak self] data in
                guard let self else { return }
                guard let data = data else {
                    self.updateIcon(data: nil)
                    return
                }
                self.updateIcon(data: data)
                self.notifications.checkAndNotify(data: data)
            }
            .store(in: &cancellables)

        service.$needsLogin
            .receive(on: DispatchQueue.main)
            .filter { $0 }
            .sink { [weak self] _ in self?.presentLoginWindow() }
            .store(in: &cancellables)
    }

    // MARK: - Startup + refresh timer

    private func startApp() {
        service.initialLoad()
        restartTimer()
    }

    private func restartTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            self?.service.refresh()
        }
    }

    // MARK: - Login window

    private func presentLoginWindow() {
        if loginWindowController == nil {
            let controller = LoginWindowController()
            controller.onLoginSuccess = { [weak self] in
                DispatchQueue.main.async {
                    self?.loginWindowController?.close()
                    self?.loginWindowController = nil
                    self?.service.needsLogin = false
                    self?.service.refresh()
                }
            }
            loginWindowController = controller
        }
        loginWindowController?.showWindow(nil)
        loginWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
