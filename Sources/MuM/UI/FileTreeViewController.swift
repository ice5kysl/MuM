import AppKit

/// 第 2 栏：当前项目的目录树。
///
/// 只画一个项目的树，不做项目切换 —— 切换是第 1 栏的职责。面板顶部用一行显示
/// 当前项目名，右侧的「⋯」放这个项目相关的动作（访达、刷新、关闭），
/// 这样第 1 栏的卡片就能保持干净，只负责"选哪个项目"。
final class FileTreeViewController: NSViewController {

    /// 用户在树里选中了一个文件
    var onSelectFile: ((FileNode) -> Void)?
    /// 右键/··· 菜单请求新建文件（点中的节点已被选中，目标目录由窗口控制器按选中项推导）
    var onNewFileRequest: (() -> Void)?
    /// 同上：新建文件夹
    var onNewFolderRequest: (() -> Void)?
    /// 行内重命名的落盘委托给窗口控制器（它要跟打开状态）；返回是否成功
    var onRenameNode: ((FileNode, String) -> Bool)?
    /// 删除（移到废纸篓）委托给窗口控制器（打开状态收尾它管）
    var onTrashNode: ((FileNode) -> Void)?

    private let switcher = ProjectSwitcherControl()
    private let menuButton = NSButton()
    private let separator = NSBox()
    private let filterField = NSSearchField()
    private let outlineView = FileTreeOutlineView()
    private let scrollView = NSScrollView()
    private let emptyState = NSView()

    /// 当前处于重命名编辑态的单元格（同时最多一个）
    private var editingCell: FileTreeCellView?

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
        // 右键菜单：点中哪行（-1 = 空白区）由菜单提供者决定内容
        outlineView.menuProvider = { [weak self] row in self?.contextMenu(forRow: row) }

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
        makeProjectMenu().popUp(
            positioning: nil,
            at: NSPoint(x: menuButton.bounds.midX, y: menuButton.bounds.minY - 4),
            in: menuButton
        )
    }

    /// ··· 菜单的内容。抽成工厂方法：每次弹出重建（状态可能变了），
    /// 诊断钩子也能直接读标题清单
    private func makeProjectMenu() -> NSMenu {
        let menu = NSMenu()
        // target=nil 走响应链，最终到 AppDelegate 的对应动作（与菜单栏同一动作）
        let newFile = NSMenuItem(title: "新建文件", action: #selector(AppDelegate.newDocument(_:)), keyEquivalent: "")
        newFile.image = Self.menuIcon("doc.badge.plus")
        menu.addItem(newFile)
        let newFolder = NSMenuItem(title: "新建文件夹", action: #selector(AppDelegate.newFolder(_:)), keyEquivalent: "")
        newFolder.image = Self.menuIcon("folder.badge.plus")
        menu.addItem(newFolder)

        menu.addItem(.separator())
        let reveal = NSMenuItem(title: "在访达中显示", action: #selector(revealProject), keyEquivalent: "")
        reveal.target = self
        reveal.image = Self.finderIcon
        menu.addItem(reveal)

        let terminal = NSMenuItem(title: TerminalOpener.menuTitle, action: #selector(openProjectInTerminal), keyEquivalent: "")
        terminal.target = self
        terminal.image = TerminalOpener.menuIcon
        menu.addItem(terminal)

        let refresh = NSMenuItem(title: "刷新文件树", action: #selector(refreshTapped), keyEquivalent: "")
        refresh.target = self
        refresh.image = Self.menuIcon("arrow.clockwise")
        menu.addItem(refresh)

        menu.addItem(.separator())
        let close = NSMenuItem(title: "关闭当前项目", action: #selector(closeProject), keyEquivalent: "")
        close.target = self
        close.image = Self.menuIcon("xmark.circle")
        menu.addItem(close)
        return menu
    }

    /// 诊断用（UITestRunner）：··· 菜单的标题清单
    var debugProjectMenuTitles: [String] { makeProjectMenu().items.map(\.title) }

    @objc private func revealProject() {
        guard let url = WorkspaceStore.shared.active?.rootURL else { return }
        ExternalOpener.reveal([url])
    }

    @objc private func openProjectInTerminal() {
        guard let url = WorkspaceStore.shared.active?.rootURL else { return }
        TerminalOpener.open(url)
    }

    @objc private func refreshTapped() {
        refreshPreservingExpansion()
    }

    @objc private func closeProject() {
        WorkspaceStore.shared.closeActive()
    }

    // MARK: - 右键菜单
    //
    // 文件管理动作的自然家是文件树右键。点中节点（FileTreeOutlineView 会先选中它）
    // 给节点操作；空白区只给新建，落在项目根 —— 所以先清空选择，
    // 让窗口控制器按"没选中"推导目标目录。

    private func contextMenu(forRow row: Int) -> NSMenu? {
        guard WorkspaceStore.shared.active != nil else { return nil }
        let menu = NSMenu()

        if row >= 0, outlineView.item(atRow: row) is FileNode {
            menu.addItem(contextItem("新建文件", #selector(contextNewFile), icon: Self.menuIcon("doc.badge.plus")))
            menu.addItem(contextItem("新建文件夹", #selector(contextNewFolder), icon: Self.menuIcon("folder.badge.plus")))
            menu.addItem(contextItem("重命名…", #selector(contextRename), icon: Self.menuIcon("pencil")))
            menu.addItem(.separator())
            menu.addItem(contextItem("在访达中显示", #selector(contextRevealInFinder), icon: Self.finderIcon))
            menu.addItem(contextItem(TerminalOpener.menuTitle, #selector(contextOpenInTerminal), icon: TerminalOpener.menuIcon))
            menu.addItem(.separator())
            menu.addItem(contextItem("移到废纸篓", #selector(contextTrash), icon: Self.menuIcon("trash")))
        } else {
            menu.addItem(contextItem("新建文件", #selector(contextNewFileAtRoot), icon: Self.menuIcon("doc.badge.plus")))
            menu.addItem(contextItem("新建文件夹", #selector(contextNewFolderAtRoot), icon: Self.menuIcon("folder.badge.plus")))
        }
        return menu
    }

    /// 菜单项的小图标：功能一眼可辨（ice 2026-09-19）。SF Symbol 统一 12pt
    private static func menuIcon(_ name: String) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        return NSImage(systemSymbolName: name, accessibilityDescription: nil)?
            .withSymbolConfiguration(config)
    }

    /// 「在访达中显示」用 Finder 自己的图标
    private static let finderIcon: NSImage? = {
        let icon = NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")
        icon.size = NSSize(width: 14, height: 14)
        return icon
    }()

    private func contextItem(_ title: String, _ action: Selector, icon: NSImage? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.image = icon
        return item
    }

    @objc private func contextNewFile() { onNewFileRequest?() }
    @objc private func contextNewFolder() { onNewFolderRequest?() }

    @objc private func contextNewFileAtRoot() {
        outlineView.deselectAll(nil)
        onNewFileRequest?()
    }

    @objc private func contextNewFolderAtRoot() {
        outlineView.deselectAll(nil)
        onNewFolderRequest?()
    }

    /// 重命名只能从菜单进 —— 单击文件名永远只是选中，不进编辑态
    @objc private func contextRename() {
        beginRenameSelected()
    }

    @objc private func contextTrash() {
        guard let node = selectedNode else { return }
        onTrashNode?(node)
    }

    @objc private func contextRevealInFinder() {
        guard let node = selectedNode else { return }
        ExternalOpener.reveal([node.url])
    }

    /// 选中的是文件夹直接开；是文件就开它所在的那层
    @objc private func contextOpenInTerminal() {
        guard let node = selectedNode else { return }
        TerminalOpener.open(node.isDirectory ? node.url : node.url.deletingLastPathComponent())
    }

    // MARK: - 行内重命名（Finder 式：回车确认、Esc 取消）
    //
    // 实现方式：直接把单元格里的 nameLabel 临时变成可编辑文本框，
    // 不换单元格类型、不叠浮层 —— view-based outline 里这是侵入最小的做法。

    /// 让 url 对应的节点进入重命名编辑态（新建文件夹后调它：名字就是文件夹的全部）
    func beginRename(url: URL) {
        reveal(url: url)
        beginRenameSelected()
    }

    /// 当前选中的节点进入重命名编辑态
    func beginRenameSelected() {
        let row = outlineView.selectedRow
        guard row >= 0,
              let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: true) as? FileTreeCellView,
              let node = cell.node else { return }
        editingCell?.cancelEditing()
        editingCell = cell
        cell.beginEditing(
            onCommit: { [weak self] newName in
                guard let self else { return false }
                self.editingCell = nil
                return self.onRenameNode?(node, newName) ?? false
            },
            onEnd: { [weak self] in self?.editingCell = nil }
        )
    }

    // MARK: - 诊断钩子（UITestRunner）

    /// 是否正处于重命名编辑态
    var debugIsRenaming: Bool { editingCell != nil }
    /// 命名单元格的文本框是否真的是第一响应者（field editor 在岗）
    var debugRenameFieldActive: Bool { editingCell?.debugFieldActive ?? false }
    /// 以当前编辑中的文本框内容提交（与回车同一条路径）
    func debugCommitRename(_ newName: String) { editingCell?.debugCommit(newName) }
    /// 取消编辑（与 Esc 同一条路径）
    func debugCancelRename() { editingCell?.cancelEditing() }

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
        let urlPath = url.realPath
        let rootPath = workspace.rootURL.realPath

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
        // 行尾悬停 ···：选中该行并弹出与右键一致的菜单
        cell.onHoverMenu = { [weak self] anchor in
            guard let self else { return }
            let row = self.outlineView.row(forItem: node)
            if row >= 0, !self.outlineView.selectedRowIndexes.contains(row) {
                self.outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
            }
            self.contextMenu(forRow: row)?.popUp(
                positioning: nil,
                at: NSPoint(x: 0, y: anchor.bounds.height + 2),
                in: anchor
            )
        }
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
    /// 悬停行尾出现的 ···：文件管理动作的行内入口（菜单内容与右键一致）
    private let hoverButton = NSButton()
    /// 悬停 ··· 被点：交回控制器弹该节点的菜单（它管选中与菜单内容）
    var onHoverMenu: ((NSView) -> Void)?
    private var rowTrackingArea: NSTrackingArea?

    /// 当前展示的节点（行内重命名时要拿它做落盘）
    private(set) var node: FileNode?

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

        // 悬停 ···：默认藏着，鼠标进出行才现身（tracking area 见 updateTrackingAreas）。
        // 行内入口比栏头 ··· 近得多 —— 要操作的就是这一行
        hoverButton.image = NSImage(systemSymbolName: "ellipsis", accessibilityDescription: "更多操作")
        hoverButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        hoverButton.isBordered = false
        hoverButton.bezelStyle = .inline
        hoverButton.contentTintColor = MuMDesign.secondaryText
        hoverButton.isHidden = true
        hoverButton.target = self
        hoverButton.action = #selector(hoverMenuTapped)
        hoverButton.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconView)
        addSubview(nameLabel)
        addSubview(pathLabel)
        addSubview(hoverButton)

        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 15),
            iconView.heightAnchor.constraint(equalToConstant: 15),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 6),
            nameLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            // 编辑态下文本框要能撑到行尾（平时被 pathLabel 或截断约束收住）
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: hoverButton.leadingAnchor, constant: -2),

            pathLabel.leadingAnchor.constraint(equalTo: nameLabel.trailingAnchor, constant: 6),
            pathLabel.trailingAnchor.constraint(lessThanOrEqualTo: hoverButton.leadingAnchor, constant: -4),
            pathLabel.centerYAnchor.constraint(equalTo: centerYAnchor),

            hoverButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            hoverButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            hoverButton.widthAnchor.constraint(equalToConstant: 18),
            hoverButton.heightAnchor.constraint(equalToConstant: 16),
        ])
    }

    func configure(with node: FileNode, showsParentPath: Bool) {
        self.node = node
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
        // 复用的单元格可能还带着上一行的悬停态
        hoverButton.isHidden = true
    }

    // MARK: - 悬停 ···

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let rowTrackingArea { removeTrackingArea(rowTrackingArea) }
        // inVisibleRect：跟随可见区域自动调整，单元格复用/行高变化都不用重挂
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        rowTrackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        // 重命名编辑态下不抢戏
        hoverButton.isHidden = editing
    }

    override func mouseExited(with event: NSEvent) {
        hoverButton.isHidden = true
    }

    @objc private func hoverMenuTapped() {
        onHoverMenu?(hoverButton)
    }

    // MARK: - 行内重命名

    /// 编辑态的三个状态：编辑中 / 用户按了 Esc / 原文备份
    private var editing = false
    private var cancelled = false
    private var originalName = ""
    private var onCommit: ((String) -> Bool)?
    private var onEnd: (() -> Void)?

    /// 进入编辑态（Finder 式：回车/焦点离开确认，Esc 取消）。
    /// onCommit 返回 false（校验失败/写不进）时恢复原文 —— 报错由提交方负责。
    func beginEditing(onCommit: @escaping (String) -> Bool, onEnd: @escaping () -> Void) {
        guard let node, !editing else { return }
        originalName = node.name
        self.onCommit = onCommit
        self.onEnd = onEnd
        editing = true
        cancelled = false

        nameLabel.isEditable = true
        nameLabel.isSelectable = true
        nameLabel.isBezeled = true
        nameLabel.delegate = self
        window?.makeFirstResponder(nameLabel)

        // 选中主名（不含扩展名），文件夹没有扩展名问题、全选
        if let editor = nameLabel.currentEditor() {
            let name = nameLabel.stringValue as NSString
            let length = node.isDirectory ? name.length : (name.deletingPathExtension as NSString).length
            editor.selectedRange = NSRange(location: 0, length: length)
        }
    }

    /// Esc 路径：标取消再结束编辑，endEditing 回调里按取消处理（恢复原文、不落盘）
    func cancelEditing() {
        guard editing else { return }
        cancelled = true
        window?.makeFirstResponder(nil)
    }

    /// 诊断用（UITestRunner）：文本框的 field editor 是否在岗
    var debugFieldActive: Bool { nameLabel.currentEditor() != nil }

    /// 诊断用（UITestRunner）：写入新名并结束编辑 —— 与"回车确认"同一条 endEditing 路径
    func debugCommit(_ newName: String) {
        guard editing else { return }
        nameLabel.stringValue = newName
        window?.makeFirstResponder(nil)
    }

    /// 焦点离开时提交（与 Finder 一致）；回车也会走到这里
    private func endEditing() {
        guard editing else { return }
        editing = false
        let committed = nameLabel.stringValue
        nameLabel.isEditable = false
        nameLabel.isSelectable = false
        nameLabel.isBezeled = false
        nameLabel.delegate = nil

        let commit = onCommit
        let end = onEnd
        onCommit = nil
        onEnd = nil

        if cancelled || committed == originalName {
            nameLabel.stringValue = originalName
        } else if commit?(committed) != true {
            // 改名失败（冲突/写不进）：恢复原文。错误已经由提交方报过
            nameLabel.stringValue = originalName
        }
        end?()
    }
}

// MARK: - NSTextFieldDelegate（行内重命名）

extension FileTreeCellView: NSTextFieldDelegate {

    /// 回车 / 焦点离开都会触发；Esc 在 doCommandBy 里先标取消
    func controlTextDidEndEditing(_ notification: Notification) {
        endEditing()
    }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.cancelOperation(_:)) {
            cancelEditing()
            return true
        }
        return false
    }
}

// MARK: - 带右键菜单的大纲视图

/// 右键菜单需要知道点中的是哪一行（还是空白区），静态的 `menu` 属性做不到。
/// 点中节点时先选中它再弹菜单 —— 菜单动作（新建/重命名）都按"当前选中"工作。
private final class FileTreeOutlineView: NSOutlineView {

    /// 参数是被右键的行（-1 = 空白区），返回该行/空白区的菜单
    var menuProvider: ((Int) -> NSMenu?)?

    override func menu(for event: NSEvent) -> NSMenu? {
        let point = convert(event.locationInWindow, from: nil)
        let row = row(at: point)
        if row >= 0, !selectedRowIndexes.contains(row) {
            selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        return menuProvider?(row)
    }
}
