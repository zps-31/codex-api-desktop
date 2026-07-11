import AppKit

final class MainWindowController: NSWindowController,
    SidebarViewControllerDelegate,
    DetailViewControllerDelegate {

    private let store: ProfileStore
    private let sidebar = SidebarViewController()
    private let detail = DetailViewController()
    private let statusLabel = NSTextField(labelWithString: "")

    init(store: ProfileStore) {
        self.store = store
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1080, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init(window: window)
        window.title = "Codex API 桌面版"
        window.center()
        window.minSize = NSSize(width: 900, height: 620)
        configureContent()
        refresh()
    }

    required init?(coder: NSCoder) { nil }

    func launchActiveProfileIfReady() {
        guard let activeProfile = store.activeProfile,
              store.hasKey(for: activeProfile) else { return }
        store.selection = activeProfile.id
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
        let officialButton = NSButton(title: "打开官方 Codex", target: self, action: #selector(openOfficial))
        officialButton.bezelStyle = .inline
        let statusStack = NSStackView(views: [statusLabel, NSView(), officialButton])
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
            statusBar.heightAnchor.constraint(equalToConstant: 34),
            statusStack.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 12),
            statusStack.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: -12),
            statusStack.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor)
        ])
        window?.contentViewController = root
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
            workingDirectory: store.workingDirectory
        )
        statusLabel.stringValue = store.statusMessage.isEmpty
            ? (store.activeProfile.map { "● 当前：\($0.name) / \($0.model)   ·   数据独立存放于 \(store.runtimeDirectory)" } ?? "尚未激活 API 配置")
            : store.statusMessage
        showPendingErrorIfNeeded()
    }

    private func update(profile: ProviderProfile, workingDirectory: String) {
        if let index = store.profiles.firstIndex(where: { $0.id == profile.id }) {
            store.profiles[index] = profile
        }
        store.selection = profile.id
        store.workingDirectory = workingDirectory
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
        store.selection = profileID
        refresh()
    }

    func sidebarDidRequestAdd(preset: ProviderPreset) {
        store.addProfile(preset)
        refresh()
    }

    func sidebarDidRequestDelete() {
        store.deleteSelected()
        refresh()
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
        store.launchSelected()
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
}
