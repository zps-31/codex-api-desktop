import AppKit

protocol DetailViewControllerDelegate: AnyObject {
    func detailDidEdit(profile: ProviderProfile, workingDirectory: String)
    func detailDidRequestSave(profile: ProviderProfile, workingDirectory: String)
    func detailDidRequestActivate(profile: ProviderProfile, workingDirectory: String)
    func detailDidRequestLaunch(profile: ProviderProfile, workingDirectory: String)
    func detailDidRequestSaveKey(_ key: String, profile: ProviderProfile)
    func detailDidRequestClearKey(profile: ProviderProfile)
}

final class DetailViewController: NSViewController {
    weak var delegate: DetailViewControllerDelegate?

    private var profile: ProviderProfile?
    private let titleLabel = NSTextField(labelWithString: "选择一个 API 配置")
    private let subtitleLabel = NSTextField(labelWithString: "")
    private let activeBadge = NSTextField(labelWithString: "")
    private let presetPopup = NSPopUpButton()
    private let nameField = NSTextField()
    private let baseURLField = NSTextField()
    private let modelField = NSTextField()
    private let authPopup = NSPopUpButton()
    private let headerLabel = NSTextField(labelWithString: "认证请求头")
    private let headerField = NSTextField()
    private let keyField = NSSecureTextField()
    private let keyStatusLabel = NSTextField(labelWithString: "")
    private let saveKeyButton = NSButton(title: "保存密钥", target: nil, action: nil)
    private let clearKeyButton = NSButton(title: "移除", target: nil, action: nil)
    private let workingDirectoryField = NSTextField()
    private let formStack = NSStackView()
    private let authHeaderRow = NSStackView()
    private let keyRow = NSStackView()

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        view = root

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scroll)

        let document = NSView()
        scroll.documentView = document
        document.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.lineBreakMode = .byTruncatingMiddle
        activeBadge.textColor = .systemGreen
        activeBadge.font = .systemFont(ofSize: 12, weight: .semibold)

        let headerText = NSStackView(views: [titleLabel, subtitleLabel])
        headerText.orientation = .vertical
        headerText.spacing = 5
        let header = NSStackView(views: [headerText, NSView(), activeBadge])
        header.orientation = .horizontal
        header.alignment = .top

        presetPopup.addItems(withTitles: ProviderPreset.allCases.map(\.title))
        presetPopup.target = self
        presetPopup.action = #selector(presetChanged)
        authPopup.addItems(withTitles: AuthenticationMode.allCases.map(\.title))
        authPopup.target = self
        authPopup.action = #selector(authChanged)

        let providerBox = makeBox(title: "供应商与模型", rows: [
            formRow("配置模板", presetPopup),
            formRow("配置名称", nameField),
            formRow("API Base URL", baseURLField),
            formRow("模型 ID", modelField),
            formRow("接口协议", NSTextField(labelWithString: "Responses API"))
        ])

        headerField.placeholderString = "例如 api-key"
        authHeaderRow.orientation = .horizontal
        authHeaderRow.spacing = 12
        authHeaderRow.distribution = .fill
        authHeaderRow.addArrangedSubview(headerLabel)
        authHeaderRow.addArrangedSubview(headerField)
        headerLabel.widthAnchor.constraint(equalToConstant: 120).isActive = true
        headerField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        headerField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        keyField.placeholderString = "粘贴 API Key；现有密钥不会显示"
        saveKeyButton.target = self
        saveKeyButton.action = #selector(saveKey)
        clearKeyButton.target = self
        clearKeyButton.action = #selector(clearKey)
        clearKeyButton.hasDestructiveAction = true
        keyRow.orientation = .horizontal
        keyRow.spacing = 8
        keyRow.distribution = .fill
        keyRow.addArrangedSubview(keyField)
        keyRow.addArrangedSubview(saveKeyButton)
        keyRow.addArrangedSubview(clearKeyButton)
        keyField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        keyField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let credentialBox = makeBox(title: "API 凭据", rows: [
            formRow("认证方式", authPopup),
            authHeaderRow,
            keyRow,
            keyStatusLabel
        ])

        let chooseButton = NSButton(title: "选择…", target: self, action: #selector(chooseDirectory))
        let pathRow = NSStackView(views: [workingDirectoryField, chooseButton])
        pathRow.orientation = .horizontal
        pathRow.spacing = 8
        pathRow.distribution = .fill
        workingDirectoryField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        workingDirectoryField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let workspaceBox = makeBox(title: "启动位置", rows: [pathRow])

        let saveButton = NSButton(title: "保存", target: self, action: #selector(saveConfiguration))
        saveButton.keyEquivalent = "s"
        saveButton.keyEquivalentModifierMask = .command
        let activateButton = NSButton(title: "设为当前", target: self, action: #selector(activateProfile))
        let launchButton = NSButton(title: "启动 Codex 桌面 API 版", target: self, action: #selector(launchProfile))
        launchButton.bezelColor = .controlAccentColor
        launchButton.keyEquivalent = "\r"
        launchButton.keyEquivalentModifierMask = .command
        let actions = NSStackView(views: [NSView(), saveButton, activateButton, launchButton])
        actions.orientation = .horizontal
        actions.spacing = 9

        let note = NSTextField(wrappingLabelWithString: "ⓘ 将启动独立的 Codex 桌面实例，不再打开终端。CCTQ GPT-5.6 使用 Sol / Terra / Luna 三个模型 ID；它们共享 https://www.cctq.ai/v1、Responses、OPENAI_API_KEY，并关闭 WebSocket。若某个模型返回 503，表示 CCTQ 该模型后端暂时不可用。")
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 12)

        formStack.orientation = .vertical
        formStack.spacing = 18
        formStack.alignment = .leading
        [header, providerBox, credentialBox, workspaceBox, note, actions].forEach {
            formStack.addArrangedSubview($0)
            $0.widthAnchor.constraint(equalTo: formStack.widthAnchor).isActive = true
        }
        formStack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(formStack)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: root.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            document.heightAnchor.constraint(greaterThanOrEqualTo: scroll.contentView.heightAnchor),
            formStack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 28),
            formStack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -28),
            formStack.topAnchor.constraint(equalTo: document.topAnchor, constant: 26),
            formStack.bottomAnchor.constraint(lessThanOrEqualTo: document.bottomAnchor, constant: -26)
        ])
        formStack.isHidden = true
    }

    func reload(profile: ProviderProfile?, active: Bool, hasKey: Bool, workingDirectory: String) {
        self.profile = profile
        guard let profile else {
            formStack.isHidden = true
            return
        }
        formStack.isHidden = false
        titleLabel.stringValue = profile.name
        subtitleLabel.stringValue = "\(profile.model)  ·  \(profile.baseURL)"
        activeBadge.stringValue = active ? "● 当前使用" : ""
        presetPopup.selectItem(at: ProviderPreset.allCases.firstIndex(of: profile.preset) ?? 0)
        nameField.stringValue = profile.name
        baseURLField.stringValue = profile.baseURL
        modelField.stringValue = profile.model
        authPopup.selectItem(at: AuthenticationMode.allCases.firstIndex(of: profile.authenticationMode) ?? 0)
        headerField.stringValue = profile.authenticationHeader
        workingDirectoryField.stringValue = workingDirectory
        keyField.stringValue = ""
        keyStatusLabel.stringValue = hasKey ? "🔒 密钥已保存在 macOS 钥匙串" : "尚未保存密钥"
        keyStatusLabel.textColor = hasKey ? .systemGreen : .secondaryLabelColor
        clearKeyButton.isEnabled = hasKey
        updateAuthenticationVisibility()
    }

    private func draftProfile() -> ProviderProfile? {
        guard var profile else { return nil }
        profile.name = nameField.stringValue
        profile.baseURL = baseURLField.stringValue
        profile.model = modelField.stringValue
        profile.authenticationMode = AuthenticationMode.allCases[max(0, authPopup.indexOfSelectedItem)]
        profile.authenticationHeader = headerField.stringValue
        return profile
    }

    private func makeBox(title: String, rows: [NSView]) -> NSBox {
        let box = NSBox()
        box.title = title
        box.boxType = .primary
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .width
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 10, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.contentView = stack
        let rowHeight = CGFloat(rows.count) * 34
        box.heightAnchor.constraint(equalToConstant: rowHeight + 42).isActive = true
        return box
    }

    private func formRow(_ label: String, _ control: NSView) -> NSStackView {
        let labelField = NSTextField(labelWithString: label)
        labelField.alignment = .right
        labelField.widthAnchor.constraint(equalToConstant: 120).isActive = true
        let row = NSStackView(views: [labelField, control])
        row.orientation = .horizontal
        row.spacing = 12
        row.alignment = .centerY
        row.distribution = .fill
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return row
    }

    @objc private func presetChanged() {
        guard var profile else { return }
        profile.applyPreset(ProviderPreset.allCases[max(0, presetPopup.indexOfSelectedItem)])
        reload(profile: profile, active: false, hasKey: false, workingDirectory: workingDirectoryField.stringValue)
        delegate?.detailDidEdit(profile: profile, workingDirectory: workingDirectoryField.stringValue)
    }

    @objc private func authChanged() { updateAuthenticationVisibility() }

    private func updateAuthenticationVisibility() {
        let mode = AuthenticationMode.allCases[max(0, authPopup.indexOfSelectedItem)]
        authHeaderRow.isHidden = mode != .customHeader
        keyRow.isHidden = !mode.needsKey
        keyStatusLabel.isHidden = !mode.needsKey
    }

    @objc private func saveConfiguration() {
        guard let profile = draftProfile() else { return }
        delegate?.detailDidRequestSave(profile: profile, workingDirectory: workingDirectoryField.stringValue)
    }

    @objc private func activateProfile() {
        guard let profile = draftProfile() else { return }
        delegate?.detailDidRequestActivate(profile: profile, workingDirectory: workingDirectoryField.stringValue)
    }

    @objc private func launchProfile() {
        guard let profile = draftProfile() else { return }
        delegate?.detailDidRequestLaunch(profile: profile, workingDirectory: workingDirectoryField.stringValue)
    }

    @objc private func saveKey() {
        guard let profile = draftProfile(), !keyField.stringValue.isEmpty else { return }
        delegate?.detailDidRequestSaveKey(keyField.stringValue, profile: profile)
        keyField.stringValue = ""
    }

    @objc private func clearKey() {
        guard let profile = draftProfile() else { return }
        delegate?.detailDidRequestClearKey(profile: profile)
    }

    @objc private func chooseDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: workingDirectoryField.stringValue)
        if panel.runModal() == .OK, let url = panel.url {
            workingDirectoryField.stringValue = url.path
        }
    }
}
