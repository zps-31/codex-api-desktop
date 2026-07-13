import AppKit

protocol SidebarViewControllerDelegate: AnyObject {
    func sidebarDidSelect(profileID: UUID?)
    func sidebarDidRequestAdd(preset: ProviderPreset)
    func sidebarDidRequestDuplicate()
    func sidebarDidRequestDelete()
}

final class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    weak var delegate: SidebarViewControllerDelegate?

    private let tableView = NSTableView()
    private let presetPopup = NSPopUpButton()
    private let duplicateButton = NSButton()
    private let removeButton = NSButton()
    private var profiles: [ProviderProfile] = []
    private var activeProfileID: UUID?
    private var isReloadingSelection = false

    override func loadView() {
        let effect = NSVisualEffectView()
        effect.material = .sidebar
        effect.blendingMode = .behindWindow
        effect.state = .active
        view = effect

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("profile"))
        column.title = "API 配置"
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowHeight = 62
        tableView.delegate = self
        tableView.dataSource = self
        tableView.style = .sourceList
        tableView.backgroundColor = .clear

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        presetPopup.addItems(withTitles: ProviderPreset.creationCases.map(\.title))
        presetPopup.controlSize = .small

        let addButton = NSButton(
            image: .safeSystemSymbol("plus", accessibilityDescription: "添加"),
            target: self,
            action: #selector(addProfile)
        )
        addButton.bezelStyle = .texturedRounded
        addButton.toolTip = "添加所选模板"
        duplicateButton.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "复制")
        duplicateButton.target = self
        duplicateButton.action = #selector(duplicateProfile)
        duplicateButton.bezelStyle = .texturedRounded
        duplicateButton.toolTip = "复制当前配置"
        removeButton.image = NSImage(systemSymbolName: "trash", accessibilityDescription: "删除")
        removeButton.target = self
        removeButton.action = #selector(deleteProfile)
        removeButton.bezelStyle = .texturedRounded
        removeButton.toolTip = "删除当前配置"

        let title = NSTextField(labelWithString: "工作环境")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        let subtitle = NSTextField(labelWithString: "项目、模型与启动场景")
        subtitle.font = .systemFont(ofSize: 10)
        subtitle.textColor = .secondaryLabelColor
        let header = NSStackView(views: [title, subtitle])
        header.orientation = .vertical
        header.spacing = 2
        header.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 8, right: 12)

        let footer = NSStackView(views: [presetPopup, addButton, duplicateButton, removeButton])
        footer.orientation = .horizontal
        footer.spacing = 6
        footer.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)

        let stack = NSStackView(views: [header, scroll, footer])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            header.heightAnchor.constraint(equalToConstant: 54),
            footer.heightAnchor.constraint(equalToConstant: 42)
        ])
    }

    func reload(profiles: [ProviderProfile], selection: UUID?, activeProfileID: UUID?) {
        isReloadingSelection = true
        defer { isReloadingSelection = false }
        self.profiles = profiles
        self.activeProfileID = activeProfileID
        duplicateButton.isEnabled = selection != nil
        removeButton.isEnabled = selection != nil
        tableView.reloadData()
        if let selection, let index = profiles.firstIndex(where: { $0.id == selection }) {
            tableView.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
        } else {
            tableView.deselectAll(nil)
        }
    }

    func numberOfRows(in tableView: NSTableView) -> Int { profiles.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let profile = profiles[row]
        let cell = NSTableCellView()
        let image = NSImageView(
            image: .safeSystemSymbol(
                profile.preset.icon,
                accessibilityDescription: nil
            )
        )
        image.contentTintColor = activeProfileID == profile.id ? .systemGreen : .secondaryLabelColor
        image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)

        let title = NSTextField(labelWithString: profile.name)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        let subtitle = NSTextField(labelWithString: "\(profile.model)  ·  \(profile.workScenario.title)")
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        let workspace = NSTextField(labelWithString: profile.workspaceName)
        workspace.font = .systemFont(ofSize: 10)
        workspace.textColor = .tertiaryLabelColor
        workspace.lineBreakMode = .byTruncatingMiddle
        let labels = NSStackView(views: [title, subtitle, workspace])
        labels.orientation = .vertical
        labels.spacing = 1

        let rowStack = NSStackView(views: [image, labels])
        rowStack.orientation = .horizontal
        rowStack.spacing = 10
        rowStack.alignment = .centerY
        rowStack.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(rowStack)
        NSLayoutConstraint.activate([
            image.widthAnchor.constraint(equalToConstant: 18),
            rowStack.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8),
            rowStack.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8),
            rowStack.centerYAnchor.constraint(equalTo: cell.centerYAnchor)
        ])
        return cell
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        guard !isReloadingSelection else { return }
        let row = tableView.selectedRow
        delegate?.sidebarDidSelect(profileID: profiles.indices.contains(row) ? profiles[row].id : nil)
    }

    @objc private func addProfile() {
        let index = max(0, presetPopup.indexOfSelectedItem)
        guard ProviderPreset.creationCases.indices.contains(index) else { return }
        delegate?.sidebarDidRequestAdd(preset: ProviderPreset.creationCases[index])
    }

    @objc private func deleteProfile() {
        delegate?.sidebarDidRequestDelete()
    }

    @objc private func duplicateProfile() {
        delegate?.sidebarDidRequestDuplicate()
    }
}
