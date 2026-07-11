import AppKit

protocol SidebarViewControllerDelegate: AnyObject {
    func sidebarDidSelect(profileID: UUID?)
    func sidebarDidRequestAdd(preset: ProviderPreset)
    func sidebarDidRequestDelete()
}

final class SidebarViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {
    weak var delegate: SidebarViewControllerDelegate?

    private let tableView = NSTableView()
    private let presetPopup = NSPopUpButton()
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
        tableView.rowHeight = 50
        tableView.delegate = self
        tableView.dataSource = self
        tableView.style = .sourceList
        tableView.backgroundColor = .clear

        let scroll = NSScrollView()
        scroll.documentView = tableView
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false

        presetPopup.addItems(withTitles: ProviderPreset.allCases.map(\.title))
        presetPopup.controlSize = .small

        let addButton = NSButton(image: NSImage(systemSymbolName: "plus", accessibilityDescription: "添加")!, target: self, action: #selector(addProfile))
        addButton.bezelStyle = .texturedRounded
        addButton.toolTip = "添加所选模板"
        let removeButton = NSButton(image: NSImage(systemSymbolName: "minus", accessibilityDescription: "删除")!, target: self, action: #selector(deleteProfile))
        removeButton.bezelStyle = .texturedRounded
        removeButton.toolTip = "删除当前配置"

        let footer = NSStackView(views: [presetPopup, addButton, removeButton])
        footer.orientation = .horizontal
        footer.spacing = 6
        footer.edgeInsets = NSEdgeInsets(top: 8, left: 10, bottom: 8, right: 10)

        let stack = NSStackView(views: [scroll, footer])
        stack.orientation = .vertical
        stack.spacing = 0
        stack.translatesAutoresizingMaskIntoConstraints = false
        effect.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: effect.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: effect.trailingAnchor),
            stack.topAnchor.constraint(equalTo: effect.topAnchor),
            stack.bottomAnchor.constraint(equalTo: effect.bottomAnchor),
            footer.heightAnchor.constraint(equalToConstant: 42)
        ])
    }

    func reload(profiles: [ProviderProfile], selection: UUID?, activeProfileID: UUID?) {
        isReloadingSelection = true
        defer { isReloadingSelection = false }
        self.profiles = profiles
        self.activeProfileID = activeProfileID
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
        let image = NSImageView(image: NSImage(systemSymbolName: profile.preset.icon, accessibilityDescription: nil)!)
        image.contentTintColor = activeProfileID == profile.id ? .systemGreen : .secondaryLabelColor
        image.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 15, weight: .medium)

        let title = NSTextField(labelWithString: profile.name)
        title.font = .systemFont(ofSize: 13, weight: .medium)
        title.lineBreakMode = .byTruncatingTail
        let subtitle = NSTextField(labelWithString: profile.model)
        subtitle.font = .systemFont(ofSize: 11)
        subtitle.textColor = .secondaryLabelColor
        subtitle.lineBreakMode = .byTruncatingTail
        let labels = NSStackView(views: [title, subtitle])
        labels.orientation = .vertical
        labels.spacing = 2

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
        delegate?.sidebarDidRequestAdd(preset: ProviderPreset.allCases[index])
    }

    @objc private func deleteProfile() {
        delegate?.sidebarDidRequestDelete()
    }
}
