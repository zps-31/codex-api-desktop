import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var mainWindowController: MainWindowController?
    private var statusItem: NSStatusItem?
    private var store: ProfileStore?

    func applicationWillFinishLaunching(_ notification: Notification) {
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let existing = NSRunningApplication.runningApplications(
            withBundleIdentifier: Bundle.main.bundleIdentifier ?? "com.zps.codex-api-desktop.plus"
        ).first { $0.processIdentifier != currentPID && !$0.isTerminated }
        guard let existing else { return }
        existing.activate(options: [.activateAllWindows])
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()
        let store = ProfileStore()
        self.store = store
        let controller = MainWindowController(store: store)
        mainWindowController = controller
        configureStatusItem()
        controller.showWindow(nil)
        NSApp.activate(ignoringOtherApps: true)
        if CommandLine.arguments.contains("--launch-active") {
            controller.launchActiveProfileIfReady()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showManager()
        return true
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.image = NSImage(systemSymbolName: "switch.2", accessibilityDescription: "切换 Codex API 模型")
        item.button?.toolTip = "Codex API Plus：切换模型"
        item.menu = makeStatusMenu()
        statusItem = item
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu(title: "Codex API Plus")
        menu.delegate = self
        return menu
    }

    private func rebuildStatusMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        let current = NSMenuItem(title: store?.activeProfile.map { "当前：\($0.name) / \($0.model)" } ?? "尚未激活模型", action: nil, keyEquivalent: "")
        current.isEnabled = false
        menu.addItem(current)
        menu.addItem(.separator())

        let profilesMenu = NSMenu(title: "切换模型")
        for profile in store?.availableProfiles ?? [] {
            let row = NSMenuItem(title: "\(profile.name)  ·  \(profile.model)", action: #selector(switchProfile(_:)), keyEquivalent: "")
            row.target = self
            row.representedObject = profile.id.uuidString
            row.state = profile.id == store?.activeProfileID ? .on : .off
            profilesMenu.addItem(row)
        }
        let profilesItem = NSMenuItem(title: "切换模型", action: nil, keyEquivalent: "")
        profilesItem.submenu = profilesMenu
        menu.addItem(profilesItem)

        menu.addItem(withTitle: "显示 API Plus", action: #selector(showManager), keyEquivalent: "")
        menu.items.last?.target = self
        menu.addItem(withTitle: "显示 API Codex", action: #selector(focusAPICodex), keyEquivalent: "")
        menu.items.last?.target = self
        menu.addItem(withTitle: "打开 Codex Meter Plus", action: #selector(openMeter), keyEquivalent: "")
        menu.items.last?.target = self
        menu.addItem(withTitle: "打开 ChatGPT Classic", action: #selector(openChatGPT), keyEquivalent: "")
        menu.items.last?.target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "退出", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    @objc private func switchProfile(_ sender: NSMenuItem) {
        guard let idText = sender.representedObject as? String,
              let id = UUID(uuidString: idText) else { return }
        mainWindowController?.activateAndLaunch(profileID: id)
    }

    @objc private func showManager() {
        mainWindowController?.showWindow(nil)
        mainWindowController?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func focusAPICodex() {
        store?.focusAPICodex()
    }

    @objc private func openMeter() {
        let url = URL(fileURLWithPath: "/Applications/Codex Meter Plus.app", isDirectory: true)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    @objc private func openChatGPT() {
        ExternalAppLauncher.openChatGPT()
    }

    private func configureMainMenu() {
        let mainMenu = NSMenu()
        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)

        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 Codex API 桌面版 Plus", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 Codex API 桌面版 Plus", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        NSApp.mainMenu = mainMenu
    }
}

extension AppDelegate: NSMenuDelegate {
    func menuWillOpen(_ menu: NSMenu) {
        rebuildStatusMenu(menu)
    }
}
