import AppKit

/// ⌘P 快速打开面板：一个输入框 + 一个结果列表，挂在主窗口上的浮动面板。
///
/// 交互约定照 VS Code / Sublime 的 Quick Open：输入即过滤，↑↓ 选择，
/// ⏎ 打开并关闭，Esc 直接关闭。索引由 MainWindowController 持有（按项目缓存、
/// 后台重建），这里只管展示与按键。
final class QuickOpenPanel: NSPanel {

    /// 选中某个文件（⏎ 或点击）时回调
    var onOpen: ((URL) -> Void)?

    private let field = NSTextField()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "")

    private var results: [QuickOpenIndex.Entry] = []
    private var index: QuickOpenIndex?

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 380),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // 面板没有标题栏文字：它是一个"用完即走"的浮动层，不是文档窗口
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false

        buildContent()
    }

    override var canBecomeKey: Bool { true }

    // MARK: - 展示

    /// 在父窗口上居中弹出。索引重建由调用方负责；这里拿到什么显示什么。
    func present(over parent: NSWindow, index: QuickOpenIndex) {
        self.index = index
        parent.addChildWindow(self, ordered: .above)

        // 相对父窗口居中，跟着父窗口移动
        let frame = parent.frame
        let origin = NSPoint(
            x: frame.midX - self.frame.width / 2,
            y: frame.midY - self.frame.height / 2 + frame.height * 0.15
        )
        setFrameOrigin(origin)

        field.stringValue = ""
        refilter()
        parent.makeFirstResponder(field)
        makeKeyAndOrderFront(nil)
        parent.makeFirstResponder(field)
    }

    /// 索引重建完成后由调用方通知，列表换新但保留输入
    func indexDidUpdate() {
        refilter()
    }

    override func close() {
        parent?.removeChildWindow(self)
        super.close()
    }

    // MARK: - 过滤

    private func refilter() {
        guard let index else { return }
        results = index.matching(field.stringValue)
        tableView.reloadData()
        if !results.isEmpty {
            tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
        }
        emptyLabel.stringValue = index.entries.isEmpty ? "索引构建中…" : "没有匹配的文件"
        emptyLabel.isHidden = !results.isEmpty
    }

    private func openSelection() {
        let row = tableView.selectedRow
        guard results.indices.contains(row) else { return }
        let url = results[row].url
        close()
        onOpen?(url)
    }

    // MARK: - 界面搭建

    private func buildContent() {
        guard let contentView else { return }

        field.placeholderString = "输入文件名…"
        field.font = NSFont.systemFont(ofSize: 16)
        field.isBezeled = true
        field.bezelStyle = .roundedBezel
        field.focusRingType = .none
        field.translatesAutoresizingMaskIntoConstraints = false
        field.target = self
        field.action = #selector(fieldAction(_:))
        (field.cell as? NSTextFieldCell)?.sendsActionOnEndEditing = false
        field.delegate = self

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("file"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowSizeStyle = .custom
        tableView.rowHeight = 40
        tableView.intercellSpacing = NSSize(width: 0, height: 1)
        tableView.target = self
        tableView.doubleAction = #selector(tableDoubleClick(_:))
        tableView.dataSource = self
        tableView.delegate = self

        scrollView.documentView = tableView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.font = NSFont.systemFont(ofSize: 13)
        emptyLabel.alignment = .center
        emptyLabel.isHidden = true
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(field)
        contentView.addSubview(scrollView)
        contentView.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            field.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            field.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),

            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 10),
            scrollView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: 20),
        ])
    }

    @objc private func fieldAction(_ sender: NSTextField) {
        openSelection()
    }

    @objc private func tableDoubleClick(_ sender: NSTableView) {
        let row = sender.clickedRow
        guard results.indices.contains(row) else { return }
        let url = results[row].url
        close()
        onOpen?(url)
    }

    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

// MARK: - NSTextFieldDelegate

extension QuickOpenPanel: NSTextFieldDelegate {

    func controlTextDidChange(_ notification: Notification) {
        refilter()
    }

    /// 输入框里的特殊键：↑↓ 挪给列表，Esc 关闭；其余编辑键保持原义
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
            return true
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            close()
            return true
        default:
            return false
        }
    }

    private func moveSelection(by delta: Int) {
        guard !results.isEmpty else { return }
        let current = tableView.selectedRow
        let next = min(max(current + delta, 0), results.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }
}

// MARK: - NSTableViewDataSource / Delegate

extension QuickOpenPanel: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { results.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let entry = results[row]
        let identifier = NSUserInterfaceItemIdentifier("QuickOpenRow")
        let cell: QuickOpenRowView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? QuickOpenRowView {
            cell = reused
        } else {
            cell = QuickOpenRowView()
            cell.identifier = identifier
        }
        cell.configure(name: entry.name, path: entry.relativePath)
        return cell
    }
}

/// 一行结果：文件名（主）+ 相对路径（次）
private final class QuickOpenRowView: NSTableCellView {

    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        nameLabel.font = NSFont.systemFont(ofSize: 14, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.font = NSFont.systemFont(ofSize: 11)
        pathLabel.textColor = .secondaryLabelColor
        pathLabel.lineBreakMode = .byTruncatingHead

        let stack = NSStackView(views: [nameLabel, pathLabel])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("QuickOpenRowView 不走 nib")
    }

    func configure(name: String, path: String) {
        nameLabel.stringValue = name
        pathLabel.stringValue = path
    }
}
