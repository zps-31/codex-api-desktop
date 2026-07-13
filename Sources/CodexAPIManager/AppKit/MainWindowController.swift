import AppKit

final class MainWindowController: NSWindowController,
    NSWindowDelegate,
    SidebarViewControllerDelegate,
    DetailViewControllerDelegate {

    private let store: ProfileStore
    private let sidebar = SidebarViewController()
    private let detail = DetailViewController()
    private let statusLabel = NSTextField(labelWithString: "")
    private let currentSessionValue = NSTextField(labelWithString: "--")
    private let lastRequestValue = NSTextField(labelWithString: "--")
    private let contextValue = NSTextField(labelWithString: "--")
    private let usageMonitor = SessionUsageMonitor()
    private var usageTimer: Timer?

    init(store: ProfileStore) {
        self.store = store
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1160, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.delegate = self
        window.title = "Codex API Desktop Plus"
        window.minSize = NSSize(width: 940, height: 660)
        window.setFrameAutosaveName("CodexAPIManagerPlus.MainWindow")
        if !window.setFrameUsingName("CodexAPIManagerPlus.MainWindow") {
            window.center()
        }
        configureContent()
        refresh()
        refreshUsage()
    }

    required init?(coder: NSCoder) { nil }

    deinit { usageTimer?.invalidate() }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        refreshUsage()
        updateUsageTimer()
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        updateUsageTimer()
    }

    func windowDidMiniaturize(_ notification: Notification) {
        updateUsageTimer()
    }

    func windowDidDeminiaturize(_ notification: Notification) {
        updateUsageTimer()
    }

    func windowWillClose(_ notification: Notification) {
        stopUsageTimer()
    }

    func launchActiveProfileIfReady() {
        guard let activeProfile = store.activeProfile,
              store.isAvailable(activeProfile) else { return }
        store.selection = activeProfile.id
        store.launchSelected()
        refresh()
    }

    func activateAndLaunch(profileID: UUID) {
        store.selectProfile(profileID)
        guard let profile = store.selectedProfile else { return }
        store.activate(profile)
        guard store.activeProfileID == profileID, !store.showingError else {
            refresh()
            showWindow(nil)
            return
        }
        store.launchSelected()
        refresh()
    }

    private func configureContent() {
        sidebar.delegate = self
        detail.delegate = self

        let split = NSSplitViewController()
        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebar)
        sidebarItem.minimumThickness = 210
        sidebarItem.maximumThickness = 330
        sidebarItem.canCollapse = false
        split.addSplitViewItem(sidebarItem)
        let detailItem = NSSplitViewItem(viewController: detail)
        detailItem.minimumThickness = 650
        split.addSplitViewItem(detailItem)

        let statusBar = NSVisualEffectView()
        statusBar.material = .headerView
        statusBar.blendingMode = .withinWindow
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.lineBreakMode = .byTruncatingMiddle
        statusLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let meterButton = NSButton(title: "打开 Meter", target: self, action: #selector(openMeter))
        meterButton.bezelStyle = .inline
        let apiCodexButton = NSButton(title: "显示 API Codex", target: self, action: #selector(focusAPICodex))
        apiCodexButton.bezelStyle = .inline
        let chatGPTButton = NSButton(title: "打开 ChatGPT Classic", target: self, action: #selector(openChatGPT))
        chatGPTButton.bezelStyle = .inline
        let officialButton = NSButton(title: "打开官方 Codex", target: self, action: #selector(openOfficial))
        officialButton.bezelStyle = .inline
        let usageStack = NSStackView(views: [
            metricView(title: "当前会话", value: currentSessionValue),
            metricView(title: "最近请求", value: lastRequestValue),
            metricView(title: "上下文", value: contextValue)
        ])
        usageStack.orientation = .horizontal
        usageStack.spacing = 14
        let statusStack = NSStackView(
            views: [statusLabel, NSView(), usageStack, apiCodexButton, meterButton, chatGPTButton, officialButton]
        )
        statusStack.orientation = .horizontal
        statusStack.alignment = .centerY
        statusStack.spacing = 8
        statusStack.translatesAutoresizingMaskIntoConstraints = false
        statusBar.addSubview(statusStack)

        let root = NSViewController()
        let container = NSView()
        root.view = container
        split.view.translatesAutoresizingMaskIntoConstraints = false
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(split.view)
        container.addSubview(statusBar)
        addChildController(split, to: root)
        NSLayoutConstraint.activate([
            split.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            split.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            split.view.topAnchor.constraint(equalTo: container.topAnchor),
            split.view.bottomAnchor.constraint(equalTo: statusBar.topAnchor),
            statusBar.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            statusBar.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: 46),
            statusStack.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 12),
            statusStack.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: -12),
            statusStack.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor)
        ])
        window?.contentViewController = root
    }

    private func metricView(title: String, value: NSTextField) -> NSView {
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 9)
        label.textColor = .secondaryLabelColor
        value.font = .monospacedDigitSystemFont(ofSize: 11, weight: .medium)
        value.alignment = .right
        let stack = NSStackView(views: [label, value])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.spacing = 1
        return stack
    }

    private func refreshUsage() {
        let snapshot = usageMonitor.latest(in: store.sessionsDirectory)
        currentSessionValue.stringValue = compact(snapshot?.totalTokens)
        lastRequestValue.stringValue = compact(snapshot?.lastRequestTokens)
        contextValue.stringValue = compact(snapshot?.contextWindow)
    }

    private func updateUsageTimer() {
        guard let window,
              window.isVisible,
              !window.isMiniaturized,
              window.occlusionState.contains(.visible) else {
            stopUsageTimer()
            return
        }
        guard usageTimer == nil else { return }
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in
            self?.refreshUsage()
        }
        RunLoop.main.add(timer, forMode: .common)
        usageTimer = timer
    }

    private func stopUsageTimer() {
        usageTimer?.invalidate()
        usageTimer = nil
    }

    private func compact(_ value: Int?) -> String {
        guard let value else { return "--" }
        if value >= 1_000_000 { return String(format: "%.1fM", Double(value) / 1_000_000) }
        if value >= 1_000 { return String(format: "%.1fK", Double(value) / 1_000) }
        return value.formatted()
    }

    private func addChildController(_ child: NSViewController, to parent: NSViewController) {
        parent.addChild(child)
    }

    private func refresh() {
        sidebar.reload(
            profiles: store.profiles,
            selection: store.selection,
            activeProfileID: store.activeProfileID
        )
        let profile = store.selectedProfile
        detail.reload(
            profile: profile,
            active: profile?.id == store.activeProfileID,
            hasKey: profile.map(store.hasKey) ?? false,
            workingDirectory: store.workingDirectory,
            healthReport: profile?.id == store.healthCheckProfileID ? store.healthCheckReport : nil,
            recentLaunches: store.launchHistory.filter { record in
                profile.map { selected in
                    record.profileID.map { $0 == selected.id }
                        ?? (selected.name == record.profileName)
                } ?? false
            }
        )
        let primaryStatus = store.statusMessage.isEmpty
            ? (store.activeProfile.map { "● 当前：\($0.name) / \($0.model)   ·   数据独立存放于 \(store.runtimeDirectory)" } ?? "尚未激活 API 配置")
            : store.statusMessage
        statusLabel.stringValue = "\(primaryStatus)   ·   \(store.runtimeStatusText)"
        showPendingErrorIfNeeded()
    }

    private func update(profile: ProviderProfile, workingDirectory: String) {
        var updatedProfile = profile
        updatedProfile.workspacePath = workingDirectory
        let profileChanged = store.profiles.first(where: { $0.id == profile.id }) != updatedProfile
            || store.workingDirectory != workingDirectory
        if let index = store.profiles.firstIndex(where: { $0.id == profile.id }) {
            store.profiles[index] = updatedProfile
        }
        store.selection = profile.id
        store.workingDirectory = workingDirectory
        if profileChanged {
            store.healthCheckReport = nil
            store.healthCheckProfileID = nil
        }
    }

    private func showPendingErrorIfNeeded() {
        guard store.showingError else { return }
        store.showingError = false
        let alert = NSAlert()
        alert.messageText = "Codex API 管理器"
        alert.informativeText = store.errorMessage
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        if let window { alert.beginSheetModal(for: window) }
    }

    func sidebarDidSelect(profileID: UUID?) {
        store.selectProfile(profileID)
        refresh()
    }

    func sidebarDidRequestAdd(preset: ProviderPreset) {
        store.addProfile(preset)
        refresh()
    }

    func sidebarDidRequestDuplicate() {
        store.duplicateSelected()
        refresh()
    }

    func sidebarDidRequestDelete() {
        guard let profile = store.selectedProfile, let window else { return }
        let alert = NSAlert()
        alert.messageText = "删除“\(profile.name)”？"
        alert.informativeText = "此配置和对应钥匙串密钥将被移除，其他配置与任务记录不受影响。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "删除")
        alert.addButton(withTitle: "取消")
        alert.buttons.first?.hasDestructiveAction = true
        alert.beginSheetModal(for: window) { [weak self] response in
            guard response == .alertFirstButtonReturn else { return }
            self?.store.deleteSelected()
            self?.refresh()
        }
    }

    func detailDidEdit(profile: ProviderProfile, workingDirectory: String) {
        update(profile: profile, workingDirectory: workingDirectory)
        sidebar.reload(profiles: store.profiles, selection: store.selection, activeProfileID: store.activeProfileID)
    }

    func detailDidRequestSave(profile: ProviderProfile, workingDirectory: String) {
        update(profile: profile, workingDirectory: workingDirectory)
        store.saveProfiles()
        refresh()
    }

    func detailDidRequestActivate(profile: ProviderProfile, workingDirectory: String) {
        update(profile: profile, workingDirectory: workingDirectory)
        store.activate(profile)
        refresh()
    }

    func detailDidRequestLaunch(profile: ProviderProfile, workingDirectory: String) {
        update(profile: profile, workingDirectory: workingDirectory)
        usageMonitor.invalidate()
        store.healthCheckAndLaunch { [weak self] in self?.refresh() }
        refresh()
    }

    func detailDidRequestHealthCheck(profile: ProviderProfile, workingDirectory: String) {
        update(profile: profile, workingDirectory: workingDirectory)
        store.runHealthCheck(for: profile) { [weak self] in
            self?.refresh()
        }
        refresh()
    }

    func detailDidRequestSaveKey(_ key: String, profile: ProviderProfile) {
        update(profile: profile, workingDirectory: store.workingDirectory)
        store.saveKey(key, for: profile)
        refresh()
    }

    func detailDidRequestClearKey(profile: ProviderProfile) {
        store.clearKey(for: profile)
        refresh()
    }

    @objc private func openOfficial() {
        store.openOfficialCodex()
        refresh()
    }

    @objc private func focusAPICodex() {
        store.focusAPICodex()
        refresh()
    }

    @objc private func openMeter() {
        if ExternalAppLauncher.openMeter() {
            store.statusMessage = "已打开 Codex Meter Plus"
        } else {
            store.statusMessage = "未找到 Codex Meter Plus，可将应用放在任意常用位置后重试"
        }
        refresh()
    }

    @objc private func openChatGPT() {
        ExternalAppLauncher.openChatGPT()
    }
}
