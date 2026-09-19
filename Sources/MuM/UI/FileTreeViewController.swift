import AppKit

/// 第 2 栏：当前项目的目录树。
///
/// 只画一个项目的树，不做项目切换 —— 切换是第 1 栏的职责。面板顶部用一行显示
/// 当前项目名，右侧的「⋯」放这个项目相关的动作（访达、刷新、关闭），
/// 这样第 1 栏的卡片就能保持干净，只负责"选哪个项目"。
final class FileTreeViewController: NSViewController {

    /// 用户在树里选中了一个文件
    var onSelectFile: ((FileNode) -> Void)?

    private let switcher = ProjectSwitcherControl()
    private let menuButton = NSButton()
    private let separator = NSBox()
    private let filterField = NSSearchField()
    private let outlineView = NSOutlineView()
    private let scrollView = NSScrollView()
    private let emptyState = NSView()

    private var items: [FileNode] = []
    private var isFiltering = false

    private let cellIdentifier = NSUserInterfaceItemIdentifier("MuM.FileCell")
    private let filterBudget = 400

    // MARK: - 生命周期

    override func loadView() {
        view = NSView()
        buildHeader()
        buildFilterField()
        buildOutlineView()
        buildEmptyState()

        NotificationCenter.default.addObserver(self, selector: #selector(workspaceChanged), name: .mumActiveWorkspaceChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(fileTreeChanged), name: .mumFileTreeChanged, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(focusFilterNotification), name: .mumFocusFileFilter, object: nil)

        reload()
    }

    // MARK: - 搭建

    private func buildHeader() {
        // 项目名同时是"切到哪个项目"的入口。放在这里而不是只放个只读标签，
        // 是因为第 1 栏收起之后，这个位置就是唯一的项目切换入口了。
        switcher.translatesAutoresizingMaskIntoConstraints = false
        switcher.onSelect = { index in
            WorkspaceStore.shared.activateShortcut(index)
        }

        menuButton.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "项目操作")
        menuButton.isBordered = false
        menuButton.bezelStyle = .inline
        menuButton.contentTintColor = MuMDesign.secondaryText
        menuButton.target = self
        menuButton.action = #selector(showProjectMenu)
        menuButton.translatesAutoresizingMaskIntoConstraints = false

        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(switcher)
        view.addSubview(menuButton)
        view.addSubview(separator)

        NSLayoutConstraint.activate([
            switcher.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            switcher.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 9),
            switcher.trailingAnchor.constraint(lessThanOrEqualTo: menuButton.leadingAnchor, constant: -6),

            menuButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -11),
            menuButton.centerYAnchor.constraint(equalTo: switcher.centerYAnchor),
            menuButton.widthAnchor.constraint(equalToConstant: 20),
            menuButton.heightAnchor.constraint(equalToConstant: 20),

            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            separator.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: MuMDesign.paneHeaderHeight),
        ])
    }

    private func buildFilterField() {
        filterField.placeholderString = "过滤文件"
        filterField.font = NSFont.systemFont(ofSize: 12)
        filterField.controlSize = .small
        filterField.delegate = self
        filterField.sendsWholeSearchString = false
        filterField.sendsSearchStringImmediately = true
        filterField.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(filterField)
        NSLayoutConstraint.activate([
            filterField.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 10),
            filterField.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -10),
            filterField.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: MuMDesign.paneHeaderHeight + 8),
        ])
    }

    private func buildOutlineView() {
        let column = NSTableColumn(identifier: cellIdentifier)
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.rowSizeStyle = .custom
        outlineView.rowHeight = MuMDesign.treeRowHeight
        outlineView.indentationPerLevel = 14
        outlineView.style = .sourceList
        outlineView.backgroundColor = .clear
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.target = self
        outlineView.action = #selector(outlineClicked(_:))
        outlineView.doubleAction = #selector(outlineDoubleClicked(_:))
        outlineView.autoresizesOutlineColumn = false
        outlineView.allowsEmptySelection = true
        outlineView.selectionHighlightStyle = .regular
        outlineView.usesAlternatingRowBackgroundColors = false

        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: filterField.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func buildEmptyState() {
        emptyState.translatesAutoresizingMaskIntoConstraints = false

        let label = NSTextField(wrappingLabelWithString: "选择左侧的一个项目")
        label.font = MuMDesign.rowSubtitle
        label.textColor = MuMDesign.tertiaryText
        label.alignment = .center
        label.translatesAutoresizingMaskIntoConstraints = false

        emptyState.addSubview(label)
        view.addSubview(emptyState)

        NSLayoutConstraint.activate([
            emptyState.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyState.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: MuMDesign.paneHeaderHeight),
            emptyState.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            label.centerXAnchor.constraint(equalTo: emptyState.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: emptyState.centerYAnchor),
        ])
    }

    // MARK: - 项目菜单

    @objc private func showProjectMenu() {
        let menu = NSMenu()
        // target=nil 走响应链，最终到 AppDelegate.newDocument（与菜单栏 ⌘N 同一动作）
        let newFile = NSMenuItem(title: "新建文件", action: #selector(AppDelegate.newDocument(_:)), keyEquivalent: "")
        menu.addItem(newFile)

        menu.addItem(.separator())
        let reveal = NSMenuItem(title: "在访达中显示", action: #selector(revealProject), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)

        let refresh = NSMenuItem(title: "刷新文件树", action: #selector(refreshTapped), keyEquivalent: "")
        refresh.target = self
        menu.addItem(refresh)

        menu.addItem(.separator())
        let close = NSMenuItem(title: "关闭当前项目", action: #selector(closeProject), keyEquivalent: "")
        close.target = self
        menu.addItem(close)

        menu.popUp(
            positioning: nil,
            at: NSPoint(x: menuButton.bounds.midX, y: menuButton.bounds.minY - 4),
            in: menuButton
        )
    }

    @objc private func revealProject() {
        guard let url = WorkspaceStore.shared.active?.rootURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @objc private func refreshTapped() {
        refreshPreservingExpansion()
    }

    @objc private func closeProject() {
        WorkspaceStore.shared.closeActive()
    }

    // MARK: - 数据

    func reload() {
        let workspace = WorkspaceStore.shared.active
        let hasWorkspace = workspace != nil

        switcher.update(projectName: workspace?.name)
        emptyState.isHidden = hasWorkspace
        filterField.isHidden = !hasWorkspace
        scrollView.isHidden = !hasWorkspace

        guard hasWorkspace else {
            items = []
            outlineView.reloadData()
            return
        }

        if isFiltering {
            applyFilter(filterField.stringValue)
        } else {
            items = workspace?.root.loadChildren() ?? []
            outlineView.reloadData()
        }
    }

    /// 当前选中的节点（新建文件落在它的目录里；诊断也用它断言选中状态）
    var selectedNode: FileNode? {
        let row = outlineView.selectedRow
        guard row >= 0 else { return nil }
        return outlineView.item(atRow: row) as? FileNode
    }

    /// 让某个文件在树里被选中并滚动到可见
    func reveal(url: URL) {
        guard !isFiltering, let workspace = WorkspaceStore.shared.active else { return }

        // 路径可能穿过符号链接（/var → /private/var、链接过的 home 目录等）：
        // 树里的子节点由 FileManager 扫描得到（已解链接），而调用方传入的 URL 没解过，
        // 且 URL/NSString 的 resolvingSymlinksInPath 在这代 macOS 上不解 /var（实测）——
        // 只有 realpath(3) 与 contentsOfDirectory 的结果一致。不解析的话，链接目录下的
        // 文件永远 reveal 不到（新建文件的断言抓住了这个）
        let urlPath = Self.realPath(url)
        let rootPath = Self.realPath(workspace.rootURL)

        guard urlPath.hasPrefix(rootPath + "/") else { return }

        let components = NSString(string: urlPath).pathComponents
        let rootComponents = NSString(string: rootPath).pathComponents
        guard components.count > rootComponents.count else { return }

        var node: FileNode? = workspace.root
        for index in rootComponents.count..<components.count {
            guard let current = node else { return }
            current.loadChildren()
            let targetPath = NSString.path(withComponents: Array(components[0...index]))
            guard let next = current.children?.first(where: { $0.url.path == targetPath }) else { return }
            if next.isDirectory {
                outlineView.expandItem(next)
            }
            node = next
        }

        guard let target = node else { return }
        let row = outlineView.row(forItem: target)
        if row >= 0 {
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            outlineView.scrollRowToVisible(row)
        }
    }

    /// realpath(3)：解不开（路径不存在等）就退回原样
    private static func realPath(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }

    func focusFilter() {
        view.window?.makeFirstResponder(filterField)
    }

    func clearFilter() {
        filterField.stringValue = ""
        isFiltering = false
    }

    var currentFilter: String { filterField.stringValue }

    // MARK: - 过滤

    private func applyFilter(_ raw: String) {
        let query = raw.trimmingCharacters(in: .whitespaces)

        guard !query.isEmpty else {
            isFiltering = false
            items = WorkspaceStore.shared.active?.root.loadChildren() ?? []
            outlineView.reloadData()
            return
        }

        isFiltering = true
        guard let root = WorkspaceStore.shared.active?.root else {
            items = []
            outlineView.reloadData()
            return
        }

        var results: [FileNode] = []
        var directoryBudget = 900
        search(root, query: query, results: &results, directoryBudget: &directoryBudget)
        items = results
        outlineView.reloadData()

        if !results.isEmpty {
            outlineView.scrollRowToVisible(0)
        }
    }

    /// 递归按文件名过滤。用「目录预算」兜住最坏情况，
    /// 避免在超大仓库里输入第一个字符就卡住主线程。
    private func search(_ node: FileNode, query: String, results: inout [FileNode], directoryBudget: inout Int) {
        guard results.count < filterBudget, directoryBudget > 0 else { return }

        for child in node.loadChildren() {
            guard results.count < filterBudget, directoryBudget > 0 else { return }
            if child.isDirectory {
                directoryBudget -= 1
                search(child, query: query, results: &results, directoryBudget: &directoryBudget)
            } else if child.name.localizedCaseInsensitiveContains(query) {
                results.append(child)
            }
        }
    }

    // MARK: - 通知

    @objc private func workspaceChanged() {
        clearFilter()
        reload()
    }

    @objc private func focusFilterNotification() {
        focusFilter()
    }

    @objc private func fileTreeChanged() {
        guard !isFiltering else {
            applyFilter(filterField.stringValue)
            return
        }
        refreshPreservingExpansion()
    }

    /// 磁盘变化时保留展开状态原地刷新，而不是把树收回去让用户重新展开
    func refreshPreservingExpansion() {
        guard let workspace = WorkspaceStore.shared.active else {
            reload()
            return
        }

        let expandedPaths = captureExpandedPaths()
        for node in workspace.loadedDirectories() {
            node.invalidate()
        }
        workspace.root.invalidate()
        items = workspace.root.loadChildren()
        outlineView.reloadData()
        restoreExpansion(expandedPaths, in: workspace.root)
    }

    private func captureExpandedPaths() -> Set<String> {
        var paths: Set<String> = []
        for row in 0..<outlineView.numberOfRows {
            guard let node = outlineView.item(atRow: row) as? FileNode, node.isDirectory else { continue }
            if outlineView.isItemExpanded(node) {
                paths.insert(node.url.path)
            }
        }
        return paths
    }

    private func restoreExpansion(_ paths: Set<String>, in node: FileNode) {
        guard node.isDirectory, node.isLoaded else { return }
        for child in node.children ?? [] where child.isDirectory {
            guard paths.contains(child.url.path) else { continue }
            child.loadChildren()
            outlineView.expandItem(child)
            restoreExpansion(paths, in: child)
        }
    }

    // MARK: - 点击

    @objc private func outlineClicked(_ sender: Any?) {
        let row = outlineView.clickedRow >= 0 ? outlineView.clickedRow : outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode else { return }
        guard node.isDirectory else { return }

        if outlineView.isItemExpanded(node) {
            outlineView.collapseItem(node)
        } else {
            outlineView.expandItem(node)
        }
    }

    @objc private func outlineDoubleClicked(_ sender: Any?) {
        let row = outlineView.clickedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode, !node.isDirectory else { return }
        onSelectFile?(node)
    }
}

// MARK: - 树数据源

extension FileTreeViewController: NSOutlineViewDataSource {

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        guard let node = item as? FileNode else { return items.count }
        guard node.isDirectory else { return 0 }
        return node.loadChildren().count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        guard let node = item as? FileNode else { return items[index] }
        return node.loadChildren()[index]
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? FileNode)?.isDirectory ?? false
    }
}

// MARK: - 树代理

extension FileTreeViewController: NSOutlineViewDelegate {

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let node = item as? FileNode else { return nil }

        let cell = outlineView.makeView(withIdentifier: cellIdentifier, owner: self) as? FileTreeCellView
            ?? FileTreeCellView(identifier: cellIdentifier)
        cell.configure(with: node, showsParentPath: isFiltering)
        return cell
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
        let row = outlineView.selectedRow
        guard row >= 0, let node = outlineView.item(atRow: row) as? FileNode else { return }
        guard !node.isDirectory else { return }
        onSelectFile?(node)
    }
}

// MARK: - 过滤框

extension FileTreeViewController: NSSearchFieldDelegate {

    func controlTextDidChange(_ obj: Notification) {
        guard (obj.object as? NSSearchField) === filterField else { return }
        applyFilter(filterField.stringValue)
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            clearFilter()
            applyFilter("")
            view.window?.makeFirstResponder(outlineView)
            return true
        }
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            // 回车直接打开第一条过滤结果，键盘流不用碰鼠标
            if isFiltering, let first = items.first {
                onSelectFile?(first)
            }
            view.window?.makeFirstResponder(outlineView)
            return true
        }
        return false
    }
}

// MARK: - 文件树单元

final class FileTreeCellView: NSTableCellView {

    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")

    init(identifier: NSUserInterfaceItemIdentifier) {
        super.init(frame: .zero)
        self.identifier = identifier
        build()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
    }

    private func build() {
        iconView.translatesAutoresizingMaskIntoConstraints = false
        iconView.imageScaling = .scaleProportionallyDown

        nameLabel.translatesAutoresizingMaskIntoConstraints = false
        nameLabel.font = MuMDesign.rowTitle
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.allowsDefaultTighteningForTruncation = true

        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.font = MuMDesign.badge
        pathLabel.textColor = MuMDesign.tertiaryText
        pathLabel.lineBreakMode = .byTruncatingHead
        pathLabel.isHidden = true

        addSubview(iconView)
        addSubview(nameLabel)
        addSubview(pathLabel)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 15),
            iconView.heightAnchor.constraint(equalToConstant: 15),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            pathLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 6),
            pathLabel.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -4),
            pathLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    func configure(with node: FileNode, showsParentPath: Bool) {
        nameLabel.stringValue = node.name
        nameLabel.textColor = node.isDirectory ? MuMDesign.secondaryText : MuMDesign.primaryText
        nameLabel.font = node.isDirectory
            ? NSFont.systemFont(ofSize: 13, weight: .medium)
            : MuMDesign.rowTitle
        iconView.image = node.icon()

        if showsParentPath {
            pathLabel.stringValue = (node.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
            pathLabel.isHidden = false
        } else {
            pathLabel.isHidden = true
        }

        toolTip = node.url.path
    }
}
