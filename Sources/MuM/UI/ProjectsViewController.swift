import AppKit

/// 第 1 栏：项目列表。
///
/// 每个项目是一张两行的卡片（名称 + 路径），而不是一个文字标签 —— 打开多个同名
/// 目录时（`docs`、`website` 之类）光看名字根本分不清，路径必须常驻。
/// 卡片上带 `⌘N` 角标，鼠标点击和键盘快捷键指向同一个动作。
final class ProjectsViewController: NSViewController {

    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onAdd: (() -> Void)?
    var onReveal: ((Int) -> Void)?

    private let headerLabel = NSTextField(labelWithString: "项目")
    private let countLabel = NSTextField(labelWithString: "")
    private let addButton = NSButton()
    private let separator = NSBox()
    private let scrollView = NSScrollView()
    private let listContainer = FlippedView()
    private let stack = NSStackView()
    private let emptyState = NSView()

    // MARK: - 生命周期

    override func loadView() {
        view = NSView()
        buildHeader()
        buildList()
        buildEmptyState()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(workspacesChanged),
            name: .mumWorkspaceListChanged,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(workspacesChanged),
            name: .mumActiveWorkspaceChanged,
            object: nil
        )

        reload()
    }

    // MARK: - 搭建

    private func buildHeader() {
        headerLabel.font = MuMDesign.paneTitle
        headerLabel.textColor = MuMDesign.secondaryText
        headerLabel.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = MuMDesign.badge
        countLabel.textColor = MuMDesign.tertiaryText
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: "打开项目")
        addButton.isBordered = false
        addButton.bezelStyle = .inline
        addButton.contentTintColor = MuMDesign.secondaryText
        addButton.target = self
        addButton.action = #selector(addTapped)
        addButton.toolTip = "打开项目文件夹（⌘O）"
        addButton.translatesAutoresizingMaskIntoConstraints = false

        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(headerLabel)
        view.addSubview(countLabel)
        view.addSubview(addButton)
        view.addSubview(separator)

        NSLayoutConstraint.activate([
            headerLabel.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14),
            headerLabel.centerYAnchor.constraint(equalTo: addButton.centerYAnchor),

            countLabel.leadingAnchor.constraint(equalTo: headerLabel.trailingAnchor, constant: 6),
            countLabel.centerYAnchor.constraint(equalTo: headerLabel.centerYAnchor),

            addButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -11),
            addButton.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            addButton.widthAnchor.constraint(equalToConstant: 20),
            addButton.heightAnchor.constraint(equalToConstant: 20),

            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            separator.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: MuMDesign.paneHeaderHeight),
        ])
    }

    private func buildList() {
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(
            top: MuMDesign.paneInset,
            left: MuMDesign.paneInset,
            bottom: MuMDesign.paneInset,
            right: MuMDesign.paneInset
        )
        stack.translatesAutoresizingMaskIntoConstraints = false

        // 滚动视图的 documentView 必须关掉 autoresizing，否则它的尺寸仍由 frame 决定，
        // 内部 stack 的约束不会传导上去 —— 表现为整个列表高度为 0，一张卡片都看不见。
        listContainer.translatesAutoresizingMaskIntoConstraints = false

        listContainer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: listContainer.topAnchor),
            stack.leadingAnchor.constraint(equalTo: listContainer.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: listContainer.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: listContainer.bottomAnchor),
        ])

        scrollView.documentView = listContainer
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: MuMDesign.paneHeaderHeight + 1),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            listContainer.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])
    }

    private func buildEmptyState() {
        emptyState.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = NSImage(systemSymbolName: "rectangle.stack.badge.plus", accessibilityDescription: nil)
        icon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 26, weight: .light)
        icon.contentTintColor = MuMDesign.tertiaryText

        let title = NSTextField(labelWithString: "还没有打开的项目")
        title.font = MuMDesign.rowTitle
        title.textColor = MuMDesign.secondaryText
        title.alignment = .center

        let subtitle = NSTextField(wrappingLabelWithString: "打开一个文件夹，MuM 会记住它的位置和上次读到哪里。")
        subtitle.font = MuMDesign.rowSubtitle
        subtitle.textColor = MuMDesign.tertiaryText
        subtitle.alignment = .center
        subtitle.preferredMaxLayoutWidth = 170

        let openButton = NSButton(title: "打开文件夹…", target: self, action: #selector(addTapped))
        openButton.bezelStyle = .rounded
        openButton.bezelColor = .controlAccentColor
        openButton.keyEquivalent = "\r"

        let stack = NSStackView(views: [icon, title, subtitle, openButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.setCustomSpacing(14, after: subtitle)
        stack.translatesAutoresizingMaskIntoConstraints = false

        emptyState.addSubview(stack)
        view.addSubview(emptyState)

        NSLayoutConstraint.activate([
            emptyState.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            emptyState.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: MuMDesign.paneHeaderHeight + 1),
            emptyState.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.centerXAnchor.constraint(equalTo: emptyState.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: emptyState.centerYAnchor, constant: -20),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 190),
        ])
    }

    @objc private func addTapped() {
        onAdd?()
    }

    // MARK: - 数据

    func reload() {
        let store = WorkspaceStore.shared
        let hasProjects = !store.workspaces.isEmpty

        emptyState.isHidden = hasProjects
        scrollView.isHidden = !hasProjects
        countLabel.stringValue = hasProjects ? "\(store.count)" : ""

        for subview in stack.arrangedSubviews {
            stack.removeArrangedSubview(subview)
            subview.removeFromSuperview()
        }

        for (index, workspace) in store.workspaces.enumerated() {
            let row = ProjectRowView(
                index: index,
                name: workspace.name,
                url: workspace.rootURL,
                isActive: index == store.activeIndex
            )
            row.onSelect = { [weak self] index in self?.onSelect?(index) }
            row.onClose = { [weak self] index in self?.onClose?(index) }
            row.onReveal = { [weak self] index in self?.onReveal?(index) }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -MuMDesign.paneInset * 2).isActive = true
        }
    }

    @objc private func workspacesChanged() {
        reload()
    }
}

// MARK: - 项目行

/// 单个项目卡片：名称 + 完整路径 + ⌘N 角标。
final class ProjectRowView: NSView {

    let index: Int
    private let url: URL
    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let pathLabel = NSTextField(labelWithString: "")
    private let badgeLabel = NSTextField(labelWithString: "")

    private var isActive: Bool
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    var onSelect: ((Int) -> Void)?
    var onClose: ((Int) -> Void)?
    var onReveal: ((Int) -> Void)?

    init(index: Int, name: String, url: URL, isActive: Bool) {
        self.index = index
        self.url = url
        self.isActive = isActive
        super.init(frame: .zero)
        build(name: name, url: url)
        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build(name: String, url: URL) {
        wantsLayer = true
        layer?.cornerRadius = MuMDesign.cornerRadius
        layer?.cornerCurve = .continuous

        iconView.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = MuMDesign.rowTitle
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        pathLabel.font = MuMDesign.rowSubtitle
        pathLabel.textColor = MuMDesign.tertiaryText
        pathLabel.lineBreakMode = .byTruncatingMiddle
        pathLabel.translatesAutoresizingMaskIntoConstraints = false
        pathLabel.stringValue = (url.path as NSString).abbreviatingWithTildeInPath

        badgeLabel.font = MuMDesign.badge
        badgeLabel.stringValue = index < 9 ? "⌘\(index + 1)" : ""
        badgeLabel.translatesAutoresizingMaskIntoConstraints = false
        badgeLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        nameLabel.stringValue = name

        addSubview(iconView)
        addSubview(nameLabel)
        addSubview(pathLabel)
        addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: MuMDesign.projectRowHeight),

            iconView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 11),
            iconView.topAnchor.constraint(equalTo: topAnchor, constant: 12),
            iconView.widthAnchor.constraint(equalToConstant: 16),
            iconView.heightAnchor.constraint(equalToConstant: 16),

            nameLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 8),
            nameLabel.centerYAnchor.constraint(equalTo: iconView.centerYAnchor),
            nameLabel.trailingAnchor.constraint(lessThanOrEqualTo: badgeLabel.leadingAnchor, constant: -6),

            pathLabel.leadingAnchor.constraint(equalTo: nameLabel.leadingAnchor),
            pathLabel.topAnchor.constraint(equalTo: nameLabel.bottomAnchor, constant: 3),
            pathLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),

            badgeLabel.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -10),
            badgeLabel.centerYAnchor.constraint(equalTo: nameLabel.centerYAnchor),
        ])

        toolTip = url.path
    }

    // MARK: - 外观

    private func refresh() {
        layer?.backgroundColor = background.cgColor
        iconView.contentTintColor = isActive ? MuMDesign.accent : MuMDesign.secondaryText
        nameLabel.font = isActive ? MuMDesign.rowTitleStrong : MuMDesign.rowTitle
        nameLabel.textColor = MuMDesign.primaryText
        badgeLabel.textColor = isActive ? MuMDesign.accent : MuMDesign.tertiaryText
    }

    private var background: NSColor {
        if isActive { return MuMDesign.selectionFill }
        if isHovered { return MuMDesign.hoverFill }
        return MuMDesign.cardFill
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refresh()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        refresh()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        refresh()
    }

    // MARK: - 交互

    override func mouseDown(with event: NSEvent) {
        onSelect?(index)
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let reveal = NSMenuItem(title: "在访达中显示", action: #selector(revealTapped), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)
        menu.addItem(.separator())
        let close = NSMenuItem(title: "关闭「\(nameLabel.stringValue)」", action: #selector(closeTapped), keyEquivalent: "")
        close.target = self
        menu.addItem(close)
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }

    @objc private func closeTapped() {
        onClose?(index)
    }

    @objc private func revealTapped() {
        onReveal?(index)
    }
}

/// 从顶部开始排列的容器，让 NSStackView 在滚动视图里正确地从上往下堆
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
