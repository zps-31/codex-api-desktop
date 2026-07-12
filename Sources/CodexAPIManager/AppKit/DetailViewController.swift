import AppKit

private final class TopAlignedDocumentView: NSView {
    override var isFlipped: Bool { true }
}

protocol DetailViewControllerDelegate: AnyObject {
    func detailDidEdit(profile: ProviderProfile, workingDirectory: String)
    func detailDidRequestSave(profile: ProviderProfile, workingDirectory: String)
    func detailDidRequestActivate(profile: ProviderProfile, workingDirectory: String)
    func detailDidRequestLaunch(profile: ProviderProfile, workingDirectory: String)
    func detailDidRequestHealthCheck(profile: ProviderProfile, workingDirectory: String)
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
    private let scenarioPopup = NSPopUpButton()
    private let scenarioDescriptionLabel = NSTextField(wrappingLabelWithString: "")
    private let taskBudgetField = NSTextField()
    private let authPopup = NSPopUpButton()
    private let headerLabel = NSTextField(labelWithString: "认证请求头")
    private let headerField = NSTextField()
    private let keyField = NSSecureTextField()
    private let keyStatusLabel = NSTextField(labelWithString: "")
    private let healthStatusLabel = NSTextField(wrappingLabelWithString: "")
    private let saveKeyButton = NSButton(title: "保存密钥", target: nil, action: nil)
    private let clearKeyButton = NSButton(title: "移除", target: nil, action: nil)
    private let workingDirectoryField = NSTextField()
    private let formStack = NSStackView()
    private let authHeaderRow = NSStackView()
    private let keyRow = NSStackView()
    private let scrollView = NSScrollView()
    private let workspaceNameLabel = NSTextField(labelWithString: "")
    private let historyRows = (0..<3).map { _ in NSTextField(wrappingLabelWithString: "") }
    private weak var healthBox: NSBox?
    private weak var historyBox: NSBox?

    override func loadView() {
        let root = NSView()
        root.wantsLayer = true
        view = root

        scrollView.hasVerticalScroller = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        root.addSubview(scrollView)

        let document = TopAlignedDocumentView()
        scrollView.documentView = document
        document.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.font = .systemFont(ofSize: 24, weight: .bold)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.maximumNumberOfLines = 2
        subtitleLabel.lineBreakMode = .byTruncatingMiddle
        activeBadge.textColor = .systemGreen
        activeBadge.font = .systemFont(ofSize: 12, weight: .semibold)

        let headerIcon = NSImageView(
            image: NSImage(
                systemSymbolName: "terminal.fill",
                accessibilityDescription: "API 工作台"
            )!
        )
        headerIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 20, weight: .semibold)
        headerIcon.contentTintColor = .controlAccentColor
        headerIcon.widthAnchor.constraint(equalToConstant: 28).isActive = true
        let headerText = NSStackView(views: [titleLabel, subtitleLabel])
        headerText.orientation = .vertical
        headerText.spacing = 5
        let header = NSStackView(views: [headerIcon, headerText, NSView(), activeBadge])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12

        presetPopup.addItems(withTitles: ProviderPreset.allCases.map(\.title))
        presetPopup.target = self
        presetPopup.action = #selector(presetChanged)
        authPopup.addItems(withTitles: AuthenticationMode.allCases.map(\.title))
        authPopup.target = self
        authPopup.action = #selector(authChanged)
        scenarioPopup.addItems(withTitles: WorkScenario.allCases.map(\.title))
        scenarioPopup.target = self
        scenarioPopup.action = #selector(scenarioChanged)
        scenarioDescriptionLabel.font = .systemFont(ofSize: 11)
        scenarioDescriptionLabel.textColor = .secondaryLabelColor
        scenarioDescriptionLabel.maximumNumberOfLines = 2
        let budgetFormatter = NumberFormatter()
        budgetFormatter.numberStyle = .decimal
        budgetFormatter.minimum = 0
        budgetFormatter.maximumFractionDigits = 2
        taskBudgetField.formatter = budgetFormatter
        taskBudgetField.placeholderString = "0 表示不提醒"

        let providerBox = makeBox(title: "供应商与模型", rows: [
            formRow("配置模板", presetPopup),
            formRow("配置名称", nameField),
            formRow("API Base URL", baseURLField),
            formRow("模型 ID", modelField),
            formRow("启动场景", scenarioPopup),
            formRow("", scenarioDescriptionLabel),
            formRow("单任务预算 USD", taskBudgetField),
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

        workspaceNameLabel.font = .systemFont(ofSize: 13, weight: .semibold)
        workspaceNameLabel.textColor = .labelColor
        let chooseButton = NSButton(
            image: NSImage(systemSymbolName: "folder", accessibilityDescription: "选择项目目录")!,
            target: self,
            action: #selector(chooseDirectory)
        )
        chooseButton.toolTip = "选择项目目录"
        let pathRow = NSStackView(views: [workingDirectoryField, chooseButton])
        pathRow.orientation = .horizontal
        pathRow.spacing = 8
        pathRow.distribution = .fill
        workingDirectoryField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        workingDirectoryField.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let workspaceBox = makeBox(title: "项目工作区", rows: [
            formRow("当前项目", workspaceNameLabel),
            pathRow
        ])

        let healthButton = NSButton(
            image: NSImage(systemSymbolName: "stethoscope", accessibilityDescription: "运行检查")!,
            target: self,
            action: #selector(runHealthCheck)
        )
        healthButton.title = "运行检查"
        healthButton.imagePosition = .imageLeading
        healthStatusLabel.font = .systemFont(ofSize: 12)
        healthStatusLabel.maximumNumberOfLines = 6
        healthStatusLabel.lineBreakMode = .byWordWrapping
        let healthTitle = sectionLabel(
            title: "启动前检查",
            systemImage: "checkmark.shield"
        )
        let healthRow = NSStackView(views: [healthTitle, NSView(), healthButton])
        healthRow.orientation = .horizontal
        healthRow.alignment = .centerY
        healthRow.spacing = 8
        let healthBox = makeBox(
            title: "",
            rows: [healthRow, healthStatusLabel],
            height: 108
        )
        self.healthBox = healthBox

        let saveButton = NSButton(
            title: "保存配置",
            target: self,
            action: #selector(saveConfiguration)
        )
        saveButton.image = NSImage(
            systemSymbolName: "tray.and.arrow.down",
            accessibilityDescription: nil
        )
        configureActionButton(saveButton, minimumWidth: 108)
        saveButton.toolTip = "保存配置"
        saveButton.setAccessibilityLabel("保存配置")
        saveButton.keyEquivalent = "s"
        saveButton.keyEquivalentModifierMask = .command
        let activateButton = NSButton(
            title: "设为当前",
            target: self,
            action: #selector(activateProfile)
        )
        activateButton.image = NSImage(
            systemSymbolName: "pin.circle",
            accessibilityDescription: nil
        )
        configureActionButton(activateButton, minimumWidth: 108)
        activateButton.toolTip = "设为当前配置"
        activateButton.setAccessibilityLabel("设为当前配置")
        let launchButton = NSButton(
            title: "检查并启动",
            target: self,
            action: #selector(launchProfile)
        )
        launchButton.image = NSImage(
            systemSymbolName: "play.fill",
            accessibilityDescription: nil
        )
        configureActionButton(launchButton, minimumWidth: 128)
        launchButton.toolTip = "检查并启动 Codex 桌面 API 版"
        launchButton.setAccessibilityLabel("检查并启动 Codex 桌面 API 版")
        launchButton.bezelColor = .controlAccentColor
        launchButton.keyEquivalent = "\r"
        launchButton.keyEquivalentModifierMask = .command
        let actions = NSStackView(views: [NSView(), saveButton, activateButton, launchButton])
        actions.orientation = .horizontal
        actions.spacing = 9

        historyRows.forEach {
            $0.font = .systemFont(ofSize: 12)
            $0.textColor = .secondaryLabelColor
            $0.maximumNumberOfLines = 1
            $0.lineBreakMode = .byTruncatingMiddle
        }
        let historyTitle = sectionLabel(
            title: "最近启动记录",
            systemImage: "clock.arrow.circlepath"
        )
        let historyBox = makeBox(
            title: "",
            rows: [historyTitle] + historyRows,
            height: 118
        )
        self.historyBox = historyBox

        let note = NSTextField(wrappingLabelWithString: "启动后可直接在 Codex 输入框下方切换全部 API Plus 配置；列表名称使用配置名称。本机路由会自动选择对应中转站、真实模型和钥匙串密钥，不需要登录官方账号。")
        note.textColor = .secondaryLabelColor
        note.font = .systemFont(ofSize: 12)

        formStack.orientation = .vertical
        formStack.spacing = 18
        formStack.alignment = .leading
        [header, workspaceBox, providerBox, credentialBox, healthBox, historyBox, note, actions].forEach {
            formStack.addArrangedSubview($0)
            $0.widthAnchor.constraint(equalTo: formStack.widthAnchor).isActive = true
        }
        formStack.translatesAutoresizingMaskIntoConstraints = false
        document.addSubview(formStack)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: root.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: root.bottomAnchor),
            document.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
            document.heightAnchor.constraint(greaterThanOrEqualTo: scrollView.contentView.heightAnchor),
            formStack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 28),
            formStack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -28),
            formStack.topAnchor.constraint(equalTo: document.topAnchor, constant: 26),
            formStack.bottomAnchor.constraint(lessThanOrEqualTo: document.bottomAnchor, constant: -26)
        ])
        formStack.isHidden = true
    }

    func reload(
        profile: ProviderProfile?,
        active: Bool,
        hasKey: Bool,
        workingDirectory: String,
        healthReport: HealthCheckReport?,
        recentLaunches: [TaskBridgeRecord]
    ) {
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
        scenarioPopup.selectItem(at: WorkScenario.allCases.firstIndex(of: profile.workScenario) ?? 0)
        scenarioDescriptionLabel.stringValue = profile.workScenario.summary
        taskBudgetField.doubleValue = profile.taskBudgetUSD
        authPopup.selectItem(at: AuthenticationMode.allCases.firstIndex(of: profile.authenticationMode) ?? 0)
        headerField.stringValue = profile.authenticationHeader
        workingDirectoryField.stringValue = workingDirectory
        workspaceNameLabel.stringValue = URL(
            fileURLWithPath: workingDirectory,
            isDirectory: true
        ).lastPathComponent
        keyField.stringValue = ""
        keyStatusLabel.stringValue = hasKey ? "密钥已保存在 macOS 钥匙串" : "尚未保存密钥"
        keyStatusLabel.textColor = hasKey ? .systemGreen : .secondaryLabelColor
        clearKeyButton.isEnabled = hasKey
        updateHealthStatus(healthReport)
        updateHistory(recentLaunches)
        updateAuthenticationVisibility()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.scrollView.contentView.scroll(to: .zero)
            self.scrollView.reflectScrolledClipView(self.scrollView.contentView)
        }
    }

    private func draftProfile() -> ProviderProfile? {
        guard var profile else { return nil }
        profile.name = nameField.stringValue
        profile.baseURL = baseURLField.stringValue
        profile.model = modelField.stringValue
        profile.workScenario = WorkScenario.allCases[max(0, scenarioPopup.indexOfSelectedItem)]
        profile.taskBudgetUSD = max(0, taskBudgetField.doubleValue)
        profile.authenticationMode = AuthenticationMode.allCases[max(0, authPopup.indexOfSelectedItem)]
        profile.authenticationHeader = headerField.stringValue
        profile.workspacePath = workingDirectoryField.stringValue
        return profile
    }

    private func makeBox(
        title: String,
        rows: [NSView],
        height: CGFloat? = nil
    ) -> NSBox {
        let box = NSBox()
        box.title = title
        box.boxType = .custom
        box.borderColor = .separatorColor
        box.borderWidth = 1
        box.cornerRadius = 8
        box.fillColor = .controlBackgroundColor
        let stack = NSStackView(views: rows)
        stack.orientation = .vertical
        stack.spacing = 12
        stack.alignment = .width
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 10, right: 10)
        stack.translatesAutoresizingMaskIntoConstraints = false
        box.contentView = stack
        let rowHeight = CGFloat(rows.count) * 34
        let heightConstraint = box.heightAnchor.constraint(
            equalToConstant: height ?? rowHeight + 42
        )
        heightConstraint.identifier = "CodexAPIManagerPlus.BoxHeight"
        heightConstraint.isActive = true
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

    private func sectionLabel(title: String, systemImage: String) -> NSStackView {
        let image = NSImageView(
            image: NSImage(
                systemSymbolName: systemImage,
                accessibilityDescription: title
            )!
        )
        image.contentTintColor = .secondaryLabelColor
        image.widthAnchor.constraint(equalToConstant: 18).isActive = true
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: .semibold)
        let row = NSStackView(views: [image, label])
        row.orientation = .horizontal
        row.alignment = .centerY
        row.spacing = 7
        return row
    }

    private func configureActionButton(
        _ button: NSButton,
        minimumWidth: CGFloat
    ) {
        button.imagePosition = .imageLeading
        button.imageHugsTitle = true
        button.bezelStyle = .rounded
        button.widthAnchor.constraint(greaterThanOrEqualToConstant: minimumWidth)
            .isActive = true
    }

    @objc private func presetChanged() {
        guard var profile else { return }
        profile.applyPreset(ProviderPreset.allCases[max(0, presetPopup.indexOfSelectedItem)])
        reload(
            profile: profile,
            active: false,
            hasKey: false,
            workingDirectory: workingDirectoryField.stringValue,
            healthReport: nil,
            recentLaunches: []
        )
        delegate?.detailDidEdit(profile: profile, workingDirectory: workingDirectoryField.stringValue)
    }

    @objc private func authChanged() { updateAuthenticationVisibility() }

    @objc private func scenarioChanged() {
        let scenario = WorkScenario.allCases[max(0, scenarioPopup.indexOfSelectedItem)]
        taskBudgetField.doubleValue = scenario.recommendedTaskBudgetUSD
        guard let profile = draftProfile() else { return }
        scenarioDescriptionLabel.stringValue = profile.workScenario.summary
        delegate?.detailDidEdit(profile: profile, workingDirectory: workingDirectoryField.stringValue)
    }

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

    @objc private func runHealthCheck() {
        guard let profile = draftProfile() else { return }
        healthStatusLabel.stringValue = "正在检查 API、凭据与工作目录…"
        healthStatusLabel.textColor = .secondaryLabelColor
        delegate?.detailDidRequestHealthCheck(profile: profile, workingDirectory: workingDirectoryField.stringValue)
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
            workspaceNameLabel.stringValue = url.lastPathComponent
        }
    }

    private func updateHistory(_ records: [TaskBridgeRecord]) {
        setBoxHeight(historyBox, 102 + CGFloat(min(records.count, 3)) * 18)
        for (index, label) in historyRows.enumerated() {
            guard records.indices.contains(index) else {
                label.stringValue = index == 0
                    ? "尚未从 Plus 启动 Codex；启动后会自动记录"
                    : ""
                label.isHidden = index > 0
                continue
            }
            label.isHidden = false
            let record = records[index]
            let status = TaskBridge.isRunning(record) ? "运行中" : "已结束"
            let time = record.startedAt.formatted(date: .abbreviated, time: .shortened)
            label.stringValue = "\(status)  \(record.projectName)  ·  \(record.model)  ·  \(time)"
        }
    }

    private func updateHealthStatus(_ report: HealthCheckReport?) {
        guard let report else {
            setBoxHeight(healthBox, 108)
            healthStatusLabel.stringValue = "尚未运行检查"
            healthStatusLabel.textColor = .secondaryLabelColor
            return
        }
        setBoxHeight(
            healthBox,
            min(184, 104 + CGFloat(report.items.count) * 20)
        )
        healthStatusLabel.stringValue = report.items
            .map { item in
                let symbol = item.state == .passed ? "✓" : item.state == .warning ? "△" : "✕"
                return "\(symbol)  \(item.title)：\(item.detail)"
            }
            .joined(separator: "\n")
        if report.items.contains(where: { $0.state == .failed }) {
            healthStatusLabel.textColor = .systemRed
        } else if report.items.contains(where: { $0.state == .warning }) {
            healthStatusLabel.textColor = .systemOrange
        } else {
            healthStatusLabel.textColor = .systemGreen
        }
    }

    private func setBoxHeight(_ box: NSBox?, _ height: CGFloat) {
        box?.constraints.first {
            $0.identifier == "CodexAPIManagerPlus.BoxHeight"
        }?.constant = height
    }
}
