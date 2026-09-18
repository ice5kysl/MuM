import AppKit

/// ⌘⇧F 全局搜索面板：搜索框 + 项目范围开关 + 流式结果列表 + 状态行。
///
/// 交互约定与 ⌘P 快速打开一致（输入即搜、↑↓ 选择、⏎ 打开、Esc 收手），
/// 区别在三点：结果跨项目、边搜边出（流式）、搜索范围可视可缩 ——
/// 10 个项目全量搜是默认，但必须能一键排除某个项目，否则用户只能关项目。
final class GlobalSearchPanel: NSPanel {

    /// 点中某条结果（⏎ 或双击）时回调，参数是命中的查询词与命中本身
    var onOpen: ((String, GlobalSearchEngine.Hit) -> Void)?

    private let field = NSSearchField()
    private let scopeStack = NSStackView()
    private let tableView = NSTableView()
    private let scrollView = NSScrollView()
    private let emptyLabel = NSTextField(labelWithString: "")
    private let statusLabel = NSTextField(labelWithString: "")

    private let engine = GlobalSearchEngine()
    private var token: GlobalSearchEngine.Token?
    private var debounce: DispatchWorkItem?

    private var scopes: [GlobalSearchEngine.Scope] = []
    /// 每个项目是否在搜索范围内。默认全开，点开关排除。
    private var included: [Bool] = []
    private var hits: [GlobalSearchEngine.Hit] = []
    private var filesScanned = 0
    private var skippedLarge = 0
    private var searching = false
    private var truncated = false

    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 440),
            styleMask: [.titled, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
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

    /// 在父窗口上居中弹出。scopes 是当前所有打开的项目，关掉面板后这份清单
    /// 可能已经过时，所以每次弹出都由调用方重新传入。
    /// prefilledQuery：选中文字右键搜索等路径带来的现成查询词，立即开搜
    func present(over parent: NSWindow, scopes: [GlobalSearchEngine.Scope], prefilledQuery: String? = nil) {
        self.scopes = scopes
        included = Array(repeating: true, count: scopes.count)
        rebuildScopeChips()

        parent.addChildWindow(self, ordered: .above)
        let frame = parent.frame
        setFrameOrigin(NSPoint(
            x: frame.midX - self.frame.width / 2,
            y: frame.midY - self.frame.height / 2 + frame.height * 0.15
        ))

        field.stringValue = prefilledQuery ?? ""
        resetResults()
        updateStatus()
        parent.makeFirstResponder(field)
        makeKeyAndOrderFront(nil)
        parent.makeFirstResponder(field)

        if prefilledQuery != nil {
            // 预填就不等 150ms 去抖：用户的意图已经很明确
            restartSearch()
        }
    }

    override func close() {
        cancelSearch()
        parent?.removeChildWindow(self)
        super.close()
    }

    // MARK: - 搜索

    private var query: String {
        field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 输入变化后 150ms 再发起：全文搜索是重活，每个按键都扫一遍磁盘不划算
    private func scheduleSearch() {
        debounce?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.restartSearch() }
        debounce = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
    }

    private func cancelSearch() {
        debounce?.cancel()
        debounce = nil
        token?.cancel()
        token = nil
        searching = false
    }

    private func restartSearch() {
        cancelSearch()
        resetResults()

        let activeScopes = scopes.indices.filter { included[$0] }.map { scopes[$0] }
        guard !query.isEmpty, !activeScopes.isEmpty else {
            updateStatus()
            return
        }

        searching = true
        updateStatus()
        token = engine.search(query: query, scopes: activeScopes) { [weak self] batch in
            self?.receive(batch)
        }
    }

    private func receive(_ batch: GlobalSearchEngine.Batch) {
        // 注意：Hit.scopeIndex 是相对"发起时的 activeScopes"的，而表格行显示
        // 项目名需要映射回完整 scopes —— 发起搜索时记下当时的映射
        let mapping = scopeMapping
        let remapped = batch.hits.map { hit -> GlobalSearchEngine.Hit in
            guard hit.scopeIndex < mapping.count else { return hit }
            return GlobalSearchEngine.Hit(
                scopeIndex: mapping[hit.scopeIndex],
                fileURL: hit.fileURL, relativePath: hit.relativePath,
                kind: hit.kind, lineNumber: hit.lineNumber, lineText: hit.lineText,
                matchRangeInLine: hit.matchRangeInLine, occurrence: hit.occurrence
            )
        }

        let insertStart = hits.count
        hits.append(contentsOf: remapped)
        filesScanned = batch.filesScanned
        skippedLarge = batch.skippedLargeFiles
        truncated = batch.isTruncated

        if !remapped.isEmpty {
            tableView.beginUpdates()
            tableView.insertRows(
                at: IndexSet(integersIn: insertStart..<hits.count),
                withAnimation: .effectFade
            )
            tableView.endUpdates()
            // 首批结果落地时选中第一行，⏎ 直接可用
            if insertStart == 0 {
                tableView.selectRowIndexes(IndexSet(integer: 0), byExtendingSelection: false)
            }
        }

        if batch.isFinished {
            searching = false
        }
        updateStatus()
        emptyLabel.isHidden = !hits.isEmpty || searching
    }

    /// 本次搜索的 activeScopes 下标 → 完整 scopes 下标
    private var scopeMapping: [Int] = []

    private func resetResults() {
        scopeMapping = scopes.indices.filter { included[$0] }
        hits = []
        filesScanned = 0
        skippedLarge = 0
        truncated = false
        tableView.reloadData()
        emptyLabel.isHidden = true
    }

    private func updateStatus() {
        if query.isEmpty {
            statusLabel.stringValue = "在 \(scopes.count) 个项目中搜索文件名和内容"
        } else if searching {
            statusLabel.stringValue = "搜索中… 已扫 \(filesScanned) 个文件（Esc 关闭）"
        } else {
            var parts = ["\(hits.count) 条结果 · 共扫 \(filesScanned) 个文件"]
            if skippedLarge > 0 {
                parts.append("已跳过 \(skippedLarge) 个超过 10MB 的文件")
            }
            if truncated {
                parts.append("结果过多已截断，请把查询写得更具体")
            }
            statusLabel.stringValue = parts.joined(separator: " · ")
        }
        emptyLabel.stringValue = emptyLabelText
    }

    private var emptyLabelText: String {
        if !query.isEmpty, scopes.indices.filter({ included[$0] }).isEmpty {
            return "所有项目都被排除了"
        }
        return searching ? "搜索中…" : "没有匹配"
    }

    // MARK: - 范围开关

    private func rebuildScopeChips() {
        for view in scopeStack.arrangedSubviews { view.removeFromSuperview() }
        for (index, scope) in scopes.enumerated() {
            let chip = NSButton(checkboxWithTitle: scope.name, target: self, action: #selector(chipToggled(_:)))
            chip.tag = index
            chip.state = included[index] ? .on : .off
            chip.font = MuMDesign.rowSubtitle
            chip.controlSize = .small
            chip.contentTintColor = MuMDesign.secondaryText
            if index < 9 {
                chip.toolTip = "⌥\(index + 1) 切换这个项目"
            }
            scopeStack.addArrangedSubview(chip)
        }
    }

    @objc private func chipToggled(_ sender: NSButton) {
        guard scopes.indices.contains(sender.tag) else { return }
        included[sender.tag] = sender.state == .on
        // 范围变了立即重搜 —— 收窄是搜索动作的一部分，不该要用户再敲一下回车
        restartSearch()
    }

    /// ⌥1…⌥9 切换对应项目的开关：收窄范围也不依赖鼠标。
    /// 面板是 key window 时数字键在输入框里是打字，加 ⌥ 才不冲突。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.modifierFlags.contains(.option),
           let chars = event.charactersIgnoringModifiers,
           let char = chars.first,
           let digit = Int(String(char)),
           digit >= 1, digit <= 9 {
            let index = digit - 1
            guard scopes.indices.contains(index) else { return true }
            included[index].toggle()
            rebuildScopeChips()
            restartSearch()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    // MARK: - 打开

    private func openSelection() {
        let row = tableView.selectedRow
        guard hits.indices.contains(row) else { return }
        let hit = hits[row]
        let currentQuery = query
        close()
        onOpen?(currentQuery, hit)
    }

    // MARK: - 界面搭建

    private func buildContent() {
        guard let contentView else { return }

        field.placeholderString = "在所有项目中搜索…"
        field.font = NSFont.systemFont(ofSize: 16)
        field.focusRingType = .none
        field.sendsSearchStringImmediately = true
        field.sendsWholeSearchString = false
        field.translatesAutoresizingMaskIntoConstraints = false
        field.target = self
        field.action = #selector(fieldAction(_:))
        field.delegate = self

        // 范围开关行：能看出"在搜哪几个项目"，点一下就能排除
        scopeStack.orientation = .horizontal
        scopeStack.spacing = 10
        scopeStack.translatesAutoresizingMaskIntoConstraints = false

        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("hit"))
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.rowSizeStyle = .custom
        tableView.rowHeight = 44
        tableView.intercellSpacing = NSSize(width: 0, height: 4)
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

        statusLabel.font = MuMDesign.status
        statusLabel.textColor = MuMDesign.tertiaryText
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        let separator = NSView()
        separator.wantsLayer = true
        separator.layer?.backgroundColor = MuMDesign.separator.cgColor
        separator.translatesAutoresizingMaskIntoConstraints = false

        contentView.addSubview(field)
        contentView.addSubview(scopeStack)
        contentView.addSubview(scrollView)
        contentView.addSubview(emptyLabel)
        contentView.addSubview(separator)
        contentView.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            field.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            field.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            field.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 14),

            scopeStack.leadingAnchor.constraint(equalTo: field.leadingAnchor),
            scopeStack.trailingAnchor.constraint(lessThanOrEqualTo: field.trailingAnchor),
            scopeStack.topAnchor.constraint(equalTo: field.bottomAnchor, constant: 8),
            scopeStack.heightAnchor.constraint(equalToConstant: 18),

            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: scopeStack.bottomAnchor, constant: 8),
            scrollView.bottomAnchor.constraint(equalTo: separator.topAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: contentView.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor, constant: 20),

            separator.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            separator.bottomAnchor.constraint(equalTo: statusLabel.topAnchor, constant: -6),
            separator.heightAnchor.constraint(equalToConstant: 1),

            statusLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            statusLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -8),
        ])
    }

    @objc private func fieldAction(_ sender: NSTextField) {
        openSelection()
    }

    @objc private func tableDoubleClick(_ sender: NSTableView) {
        let row = sender.clickedRow
        guard hits.indices.contains(row) else { return }
        let hit = hits[row]
        let currentQuery = query
        close()
        onOpen?(currentQuery, hit)
    }

    /// Esc：关闭面板。close 里会取消进行中的搜索 —— 先停再关的两段式
    /// 反直觉（ice 实测按 Esc 面板不消失），关闭本身就是"立即停"
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}

// MARK: - NSTextFieldDelegate

extension GlobalSearchPanel: NSSearchFieldDelegate {

    func controlTextDidChange(_ notification: Notification) {
        scheduleSearch()
    }

    /// 输入框里的特殊键：↑↓ 挪给列表，Esc 关面板
    func control(_ control: NSControl, textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.moveUp(_:)):
            moveSelection(by: -1)
            return true
        case #selector(NSResponder.moveDown(_:)):
            moveSelection(by: 1)
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            cancelOperation(control)
            return true
        default:
            return false
        }
    }

    private func moveSelection(by delta: Int) {
        guard !hits.isEmpty else { return }
        let current = tableView.selectedRow
        let next = min(max(current + delta, 0), hits.count - 1)
        tableView.selectRowIndexes(IndexSet(integer: next), byExtendingSelection: false)
        tableView.scrollRowToVisible(next)
    }
}

// MARK: - NSTableViewDataSource / Delegate

extension GlobalSearchPanel: NSTableViewDataSource, NSTableViewDelegate {

    func numberOfRows(in tableView: NSTableView) -> Int { hits.count }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        let hit = hits[row]
        let identifier = NSUserInterfaceItemIdentifier("GlobalSearchRow")
        let cell: GlobalSearchRowView
        if let reused = tableView.makeView(withIdentifier: identifier, owner: nil) as? GlobalSearchRowView {
            cell = reused
        } else {
            cell = GlobalSearchRowView()
            cell.identifier = identifier
        }
        let projectName = scopes.indices.contains(hit.scopeIndex) ? scopes[hit.scopeIndex].name : "?"
        cell.configure(hit: hit, projectName: projectName, query: query)
        return cell
    }
}

/// 一行结果。
/// 文件名命中：文件名（主）+ 项目名 › 相对路径（次）。
/// 内容命中：项目名 › 相对路径 · 行号（主）+ 命中行上下文、命中词高亮（次）。
private final class GlobalSearchRowView: NSTableCellView {

    private let titleLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.lineBreakMode = .byTruncatingMiddle
        detailLabel.font = NSFont.systemFont(ofSize: 11)
        detailLabel.textColor = MuMDesign.secondaryText
        detailLabel.lineBreakMode = .byTruncatingTail

        let stack = NSStackView(views: [titleLabel, detailLabel])
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
        fatalError("GlobalSearchRowView 不走 nib")
    }

    func configure(hit: GlobalSearchEngine.Hit, projectName: String, query: String) {
        switch hit.kind {
        case .fileName:
            titleLabel.stringValue = hit.fileURL.lastPathComponent
            detailLabel.stringValue = "\(projectName) › \(hit.relativePath)"

        case .content:
            titleLabel.stringValue = "\(projectName) › \(hit.relativePath) · 第 \(hit.lineNumber) 行"
            // 原始行整行铺进来是一堵字墙：折叠空白、以命中为中心开窗
            let context = GlobalSearchEngine.displayContext(
                line: hit.lineText, match: hit.matchRangeInLine)
            detailLabel.attributedStringValue = highlighted(line: context.text, match: context.matchRange)
        }
    }

    /// 命中词在上下文里加亮：用 accent 色而不是粗体 —— 列表行高有限，
    /// 粗体会让中英文混排的行 jitter，颜色不会
    private func highlighted(line: String, match: NSRange?) -> NSAttributedString {
        let attributed = NSMutableAttributedString(
            string: line,
            attributes: [
                .font: NSFont.systemFont(ofSize: 11),
                .foregroundColor: MuMDesign.secondaryText,
            ]
        )
        if let match, match.location != NSNotFound,
           match.location + match.length <= (line as NSString).length {
            attributed.addAttributes([
                .foregroundColor: MuMDesign.accent,
                .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
            ], range: match)
        }
        return attributed
    }
}
