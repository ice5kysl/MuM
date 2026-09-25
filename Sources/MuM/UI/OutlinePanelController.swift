import AppKit

/// 右侧大纲栏（ToC）。唯一的目录界面（⌘⇧O 开合；popover 已于 0.7.8 移除）。
///
/// 常驻导航：列出标题（多级可折叠）、点击跳转、跟随滚动高亮当前节。
/// 右上角「›」收成窄条（rail）贴着右缘——留一个随时拉回来的把手；
/// 窄条上的「×」彻底关掉（菜单/快捷键再开）。
final class OutlinePanelController: NSViewController {

    var onSelect: ((Int) -> Void)?
    /// 头部「›」收起按钮（交窗口控制器切到窄条态）
    var onCollapseRequest: (() -> Void)?

    private var items: [MarkdownRenderer.OutlineItem] = []
    private var rowButtons: [OutlineRowButton] = []
    private var hasChildren: [Bool] = []
    private var collapsed: Set<Int> = []
    private var currentIndex: Int?

    private let stack = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "这篇文档没有标题")
    private let scrollView = NSScrollView()
    /// documentView 用翻转容器：不翻转的 documentView 在内容不足一屏时会被
    /// AppKit 沉底（行跑到面板底部），翻转后从顶部排
    private final class FlippedView: NSView { override var isFlipped: Bool { true } }
    private let stackContainer = FlippedView()
    override func loadView() {
        // 底色走动态面板色（跟随外观），左缘 1pt 细线与正文区隔开（压淡，不抢正文）
        let background = PaneBackgroundView(color: MuMDesign.paneBackground)
        view = background

        let separator = NSBox()
        separator.boxType = .custom
        separator.borderWidth = 0
        separator.fillColor = MuMDesign.separator.withAlphaComponent(0.5)
        separator.translatesAutoresizingMaskIntoConstraints = false

        // 不放「大纲」标题字 —— 栏本身就是大纲，标题是冗余（ice 2026-09-25）。
        // 收成窄条：「›」放左上、贴着与正文区分隔线的一侧
        let collapse = NSButton()
        collapse.isBordered = false
        collapse.title = ""

        collapse.image = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)?
            .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
        collapse.contentTintColor = MuMDesign.tertiaryText
        collapse.toolTip = "收起大纲栏（⇧⌘O 再开）"
        collapse.target = self
        collapse.action = #selector(collapseTapped)
        collapse.translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 8, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = NSFont.systemFont(ofSize: 11)
        emptyLabel.textColor = MuMDesign.tertiaryText
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true

        // 约束驱动的 documentView 必须关掉 autoresizing 约束，
        // 否则它的 frame 停在 0×0，整栏行全塌掉（实测）
        stackContainer.translatesAutoresizingMaskIntoConstraints = false
        scrollView.documentView = stackContainer
        stackContainer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: stackContainer.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: stackContainer.trailingAnchor),
            stack.topAnchor.constraint(equalTo: stackContainer.topAnchor),
            stack.bottomAnchor.constraint(equalTo: stackContainer.bottomAnchor),
        ])
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(separator)
        view.addSubview(collapse)
        view.addSubview(scrollView)
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            separator.topAnchor.constraint(equalTo: view.topAnchor),
            separator.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),

            collapse.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 8),
            collapse.topAnchor.constraint(equalTo: view.topAnchor, constant: 6),
            collapse.widthAnchor.constraint(equalToConstant: 18),
            collapse.heightAnchor.constraint(equalToConstant: 18),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: collapse.bottomAnchor, constant: 2),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: collapse.bottomAnchor, constant: 20),

            stackContainer.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])
    }

    /// 每次重排后换入新大纲（location 针对当前渲染结果，旧的不能再用）。
    /// 折叠状态按标题+层级记着，重排后尽量还原
    func setOutline(_ rawItems: [MarkdownRenderer.OutlineItem]) {
        let previousCollapsed = collapsed
        // 全文只有一个 H1 时它是「文档标题」而不是目录条目 —— 标题带上已经有
        // 文件名，再列一遍只是啰嗦（ice 2026-09-25）。摘掉它，子级整体上提一层。
        // 多个 H1 的文档照原样列（那时每个 H1 都是真章节）。
        var items = rawItems
        if rawItems.first?.level == 1, rawItems.filter({ $0.level == 1 }).count == 1 {
            items = rawItems.dropFirst().map {
                MarkdownRenderer.OutlineItem(level: $0.level - 1, title: $0.title, location: $0.location)
            }
        }
        self.items = items
        collapsed = []
        hasChildren = items.indices.map { i in
            i + 1 < items.count && items[i + 1].level > items[i].level
        }
        currentIndex = nil

        rowButtons.forEach { $0.removeFromSuperview() }
        rowButtons = items.enumerated().map { index, item in
            let button = OutlineRowButton(item: item, hasChildren: hasChildren[index])
            button.tag = index
            button.target = self
            button.action = #selector(rowTapped(_:))
            button.onToggleDisclosure = { [weak self] in self?.toggleCollapsed(index) }
            stack.addArrangedSubview(button)
            // stack 是 leading 对齐，行宽必须显式钉满（否则缩进行会被量残）
            button.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            return button
        }
        emptyLabel.isHidden = !items.isEmpty

        // 同位置同层级的折叠状态还原（标题变了就不还，宁可展开）
        if !previousCollapsed.isEmpty {
            collapsed = previousCollapsed.filter { $0 < items.count }
            applyVisibility()
        }
    }

    /// 跟随滚动：把「视口顶对应的渲染位置」映射到最近的上文标题并高亮。
    /// 二分，O(log n)，滚动事件里可调。
    func setCurrentLocation(_ renderedOffset: Int) {
        guard !items.isEmpty else { return }
        var lo = 0
        // 最后一个 location <= renderedOffset 的标题
        if renderedOffset >= items[0].location {
            var hi = items.count - 1
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if items[mid].location <= renderedOffset { lo = mid } else { hi = mid - 1 }
            }
        }
        // 当前节被折叠藏起来时，高亮落在它最近的可见祖先上
        var target = lo
        while rowButtons[target].isHidden, target > 0 { target -= 1 }
        guard target != currentIndex else { return }
        if let currentIndex { rowButtons[currentIndex].isCurrent = false }
        currentIndex = target
        rowButtons[target].isCurrent = true
        rowButtons[target].scrollToVisible(rowButtons[target].bounds)
    }

    private func toggleCollapsed(_ index: Int) {
        if collapsed.contains(index) {
            collapsed.remove(index)
        } else {
            collapsed.insert(index)
        }
        rowButtons[index].isExpanded = !collapsed.contains(index)
        applyVisibility()
    }

    /// 可见性 = 没有任何处于折叠态的祖先
    private func applyVisibility() {
        var collapsedLevels: [Int] = []
        for (i, item) in items.enumerated() {
            while let last = collapsedLevels.last, item.level <= last { collapsedLevels.removeLast() }
            rowButtons[i].isHidden = !collapsedLevels.isEmpty
            if collapsed.contains(i) { collapsedLevels.append(item.level) }
        }
    }

    @objc private func rowTapped(_ sender: NSButton) {
        guard items.indices.contains(sender.tag) else { return }
        onSelect?(items[sender.tag].location)
    }

    @objc private func collapseTapped() {
        onCollapseRequest?()
    }

    // MARK: - 诊断（UITestRunner）

    var debugRowCount: Int { rowButtons.count }
    var debugVisibleRowCount: Int { rowButtons.filter { !$0.isHidden }.count }
    var debugFirstRowTitle: String? { items.first?.title }
    var debugCurrentTitle: String? {
        guard let currentIndex else { return nil }
        return items[currentIndex].title
    }
    func debugClickRow(_ index: Int) {
        guard rowButtons.indices.contains(index) else { return }
        rowTapped(rowButtons[index])
    }
    func debugToggleRowDisclosure(_ index: Int) {
        guard rowButtons.indices.contains(index), hasChildren[index] else { return }
        toggleCollapsed(index)
    }
}

/// 大纲里的一行。按层级缩进，层级越深字越小越淡；有子级的行带折叠三角。
///
/// 不用 attributedTitle + 段落样式：NSButton 对带缩进段落样式的标题
/// 自测量会算残（H2/H3 行塌到只剩一个字符）。标题交给真正的 NSTextField，
/// 截断、缩进、颜色都归它管；按钮只负责点击和悬停。
final class OutlineRowButton: NSButton {

    private let label: NSTextField
    private let item: MarkdownRenderer.OutlineItem
    private var disclosure: NSButton?

    /// 「读到这里」高亮：跟随滚动位置，当前节用强调色。默认 false
    var isCurrent = false {
        didSet {
            guard isCurrent != oldValue else { return }
            applyStyle()
        }
    }

    /// 折叠三角状态（有子级时才有意义）
    var isExpanded = true {
        didSet {
            disclosure?.image = NSImage(
                systemSymbolName: isExpanded ? "chevron.down" : "chevron.right",
                accessibilityDescription: nil
            )?.withSymbolConfiguration(.init(pointSize: 8, weight: .semibold))
        }
    }

    var onToggleDisclosure: (() -> Void)?

    init(item: MarkdownRenderer.OutlineItem, hasChildren: Bool = false) {
        label = NSTextField(labelWithString: item.title)
        self.item = item
        super.init(frame: .zero)

        isBordered = false
        bezelStyle = .inline
        title = ""
        toolTip = item.title

        let indent = CGFloat(item.level - 1) * 14 + 10

        if hasChildren {
            let triangle = NSButton()
            triangle.isBordered = false
            triangle.title = ""

            triangle.target = self
            triangle.action = #selector(disclosureTapped)
            triangle.contentTintColor = MuMDesign.tertiaryText
            // 图标直接装 —— didSet 在初始化阶段不触发，靠 isExpanded = true 装不上
            triangle.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 8, weight: .semibold))
            triangle.translatesAutoresizingMaskIntoConstraints = false
            addSubview(triangle)
            disclosure = triangle
            NSLayoutConstraint.activate([
                triangle.leadingAnchor.constraint(equalTo: leadingAnchor, constant: indent - 4),
                triangle.centerYAnchor.constraint(equalTo: centerYAnchor),
                triangle.widthAnchor.constraint(equalToConstant: 12),
            ])
            // 防止 disclosure 拦下本该属于整行的点击：它只管自己那一小块
            triangle.refusesFirstResponder = true
        }

        label.lineBreakMode = .byTruncatingTail
        // 不抢响应：点击和悬停都归按钮
        label.refusesFirstResponder = true
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        applyStyle()

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            // 缩进是版式的一部分；有无折叠三角的行文字左缘对齐（三角缩进位统一预留）
            label.leadingAnchor.constraint(equalTo: leadingAnchor, constant: indent + 10),
            label.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -10),
            label.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: item.level == 1 ? 26 : 22),
        ])
    }

    private func applyStyle() {
        let size: CGFloat = item.level == 1 ? 12.5 : (item.level == 2 ? 11.5 : 11)
        let weight: NSFont.Weight = (item.level == 1 || isCurrent) ? .semibold : .regular
        label.font = NSFont.systemFont(ofSize: size, weight: weight)
        label.textColor = isCurrent
            ? MuMDesign.accent
            : (item.level == 1 ? MuMDesign.primaryText : MuMDesign.secondaryText)
    }

    @objc private func disclosureTapped() {
        onToggleDisclosure?()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
