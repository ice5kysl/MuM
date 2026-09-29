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

    private let headerLabel = NSTextField(labelWithString: L10n.t("项目"))
    private var emptyTitleLabel: NSTextField?
    private var emptySubtitleLabel: NSTextField?
    private var emptyOpenButton: NSButton?
    private let countLabel = NSTextField(labelWithString: "")
    private let addButton = NSButton()
    private let separator = NSBox()
    private let scrollView = NSScrollView()
    private let listContainer = FlippedView()
    private let stack = NSStackView()
    private let emptyState = NSView()

    // 拖动排序会话：来源行降透明度，目标缝隙亮一条指示线（不落子视图、不动 stack，只显示）
    private var dragSourceIndex: Int?
    private let dropIndicator = NSView()

    // MARK: - 生命周期

    override func loadView() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(reloadStrings),
            name: L10n.didChangeNotification, object: nil
        )
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

    /// 语言切换：构建期写死的文案重挂（0.8.0）
    @objc private func reloadStrings() {
        headerLabel.stringValue = L10n.t("项目")
        addButton.image?.accessibilityDescription = L10n.t("打开项目")
        addButton.toolTip = L10n.t("打开项目文件夹（⌘O）")
        emptyTitleLabel?.stringValue = L10n.t("还没有打开的项目")
        emptySubtitleLabel?.stringValue = L10n.t("打开一个文件夹，MuM 会记住它的位置和上次读到哪里。")
        emptyOpenButton?.title = L10n.t("打开文件夹…")
    }

    private func buildHeader() {
        headerLabel.font = MuMDesign.paneTitle
        headerLabel.textColor = MuMDesign.secondaryText
        headerLabel.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = MuMDesign.badge
        countLabel.textColor = MuMDesign.tertiaryText
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        addButton.image = NSImage(systemSymbolName: "plus", accessibilityDescription: L10n.t("打开项目"))
        addButton.isBordered = false
        addButton.bezelStyle = .inline
        addButton.contentTintColor = MuMDesign.secondaryText
        addButton.target = self
        addButton.action = #selector(addTapped)
        addButton.toolTip = L10n.t("打开项目文件夹（⌘O）")
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

        dropIndicator.wantsLayer = true
        dropIndicator.layer?.backgroundColor = MuMDesign.accent.cgColor
        dropIndicator.layer?.cornerRadius = 1
        dropIndicator.isHidden = true
        listContainer.addSubview(dropIndicator)

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

        let title = NSTextField(labelWithString: L10n.t("还没有打开的项目"))
        emptyTitleLabel = title
        title.font = MuMDesign.rowTitle
        title.textColor = MuMDesign.secondaryText
        title.alignment = .center

        let subtitle = NSTextField(wrappingLabelWithString: L10n.t("打开一个文件夹，MuM 会记住它的位置和上次读到哪里。"))
        emptySubtitleLabel = subtitle
        subtitle.font = MuMDesign.rowSubtitle
        subtitle.textColor = MuMDesign.tertiaryText
        subtitle.alignment = .center
        subtitle.preferredMaxLayoutWidth = 170

        let openButton = NSButton(title: L10n.t("打开文件夹…"), target: self, action: #selector(addTapped))
        emptyOpenButton = openButton
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
            row.onDragStateChange = { [weak self] row, phase, event in
                self?.handleRowDrag(row: row, phase: phase, event: event)
            }
            stack.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -MuMDesign.paneInset * 2).isActive = true
        }
    }

    @objc private func workspacesChanged() {
        reload()
    }

    // MARK: - 拖动排序

    // 跟随浮影：源行的快照放进无边框浮动窗，只跟鼠标 Y、X 钉在原位
    private var dragGhost: NSPanel?
    private var dragGhostGrabOffset: CGFloat = 0

    private func handleRowDrag(row: ProjectRowView, phase: ProjectRowView.DragPhase, event: NSEvent) {
        switch phase {
        case .began:
            dragSourceIndex = row.index
            row.alphaValue = 0.35
            beginDragGhost(for: row, with: event)
        case .moved:
            moveDragGhost(with: event)
            updateDropIndicator(with: event)
        case .ended:
            endDragGhost()
            finishRowDrop(with: event, sourceRow: row)
        }
    }

    private func beginDragGhost(for row: ProjectRowView, with event: NSEvent) {
        guard let window = row.window else { return }
        guard let rep = row.bitmapImageRepForCachingDisplay(in: row.bounds) else { return }
        row.cacheDisplay(in: row.bounds, to: rep)
        let image = NSImage(size: row.bounds.size)
        image.addRepresentation(rep)

        let rowScreen = window.convertToScreen(row.convert(row.bounds, to: nil))
        let panel = NSPanel(
            contentRect: rowScreen,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .floating
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        let imageView = NSImageView(image: image)
        imageView.frame = NSRect(origin: .zero, size: row.bounds.size)
        panel.contentView = imageView
        panel.orderFront(nil)

        dragGhost = panel
        dragGhostGrabOffset = window.convertPoint(toScreen: event.locationInWindow).y - rowScreen.minY
    }

    private func moveDragGhost(with event: NSEvent) {
        guard let ghost = dragGhost, let window = event.window else { return }
        let mouseScreen = window.convertPoint(toScreen: event.locationInWindow)
        ghost.setFrameOrigin(NSPoint(x: ghost.frame.minX, y: mouseScreen.y - dragGhostGrabOffset))
    }

    private func endDragGhost() {
        dragGhost?.orderOut(nil)
        dragGhost = nil
    }

    /// 落点序号：listContainer 是 flipped（y 向下），返回「插到第几行之前」，越底返回行数
    private func insertionIndex(for event: NSEvent) -> Int {
        let point = listContainer.convert(event.locationInWindow, from: nil)
        for (i, row) in stack.arrangedSubviews.enumerated() {
            let midY = listContainer.convert(row.bounds, from: row).midY
            if point.y < midY { return i }
        }
        return stack.arrangedSubviews.count
    }

    private func updateDropIndicator(with event: NSEvent) {
        let index = insertionIndex(for: event)
        let rows = stack.arrangedSubviews
        let gapY: CGFloat
        if index < rows.count {
            gapY = listContainer.convert(rows[index].bounds, from: rows[index]).minY - 2
        } else if let last = rows.last {
            gapY = listContainer.convert(last.bounds, from: last).maxY + 1
        } else {
            return
        }
        dropIndicator.frame = CGRect(
            x: MuMDesign.paneInset,
            y: gapY,
            width: max(listContainer.bounds.width - MuMDesign.paneInset * 2, 0),
            height: 2
        )
        dropIndicator.isHidden = false
    }

    private func finishRowDrop(with event: NSEvent, sourceRow: ProjectRowView) {
        dropIndicator.isHidden = true
        sourceRow.alphaValue = 1
        guard let source = dragSourceIndex else { return }
        dragSourceIndex = nil

        var target = insertionIndex(for: event)
        if target > source { target -= 1 } // 抽走来源行后，落点序号跟着前移
        guard target != source, WorkspaceStore.shared.workspaces.indices.contains(target) else { return }
        WorkspaceStore.shared.move(from: source, to: target)
    }
}

// MARK: - 项目行

/// 单个项目卡片：名称 + 完整路径 + ⌘N 角标。
final class ProjectRowView: NSView {

    let index: Int
    private let url: URL
    private let gripView = GripView()
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

        gripView.translatesAutoresizingMaskIntoConstraints = false

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

        addSubview(gripView)
        addSubview(iconView)
        addSubview(nameLabel)
        addSubview(pathLabel)
        addSubview(badgeLabel)

        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: MuMDesign.projectRowHeight),

            gripView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 3),
            gripView.centerYAnchor.constraint(equalTo: centerYAnchor),
            gripView.widthAnchor.constraint(equalToConstant: 12),
            gripView.heightAnchor.constraint(equalToConstant: 16),

            iconView.leadingAnchor.constraint(equalTo: gripView.trailingAnchor, constant: 4),
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

    /// 拖动排序的阶段。不走 NSPasteboard：这是列表内部的纯重排，
    /// 借 mouseDragged 事件链就够了，少一套拖拽注册和会话对象。
    enum DragPhase { case began, moved, ended }
    var onDragStateChange: ((ProjectRowView, DragPhase, NSEvent) -> Void)? {
        didSet { gripView.onDragPhase = { [weak self] phase, event in
            guard let self else { return }
            self.onDragStateChange?(self, phase, event)
        } }
    }

    override func mouseDown(with event: NSEvent) {
        // 卡片本体只管选中。拖动只能从抓手（GripView）发起 ——
        // 所以这里不会再撞上「选中触发 reload 销毁自己」的自毁链。
        onSelect?(index)
    }

    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        let reveal = NSMenuItem(title: L10n.t("在访达中显示"), action: #selector(revealTapped), keyEquivalent: "")
        reveal.target = self
        menu.addItem(reveal)
        menu.addItem(.separator())
        let close = NSMenuItem(title: L10n.f("关闭「%@」", nameLabel.stringValue), action: #selector(closeTapped), keyEquivalent: "")
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

/// 拖拽抓手：两行三列 6 个小点。只有它能发起拖动 —— 卡片其余位置保持「点一下就选中」。
/// 悬停变小手（resetCursorRects 声明式，不用 push/pop），拖动中换握拳。
final class GripView: NSView {

    var onDragPhase: ((ProjectRowView.DragPhase, NSEvent) -> Void)?

    private var downPoint: NSPoint?
    private var isDragging = false

    override func draw(_ dirtyRect: NSRect) {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            MuMDesign.tertiaryText.setFill()
            let dot: CGFloat = 2.4
            let colGap: CGFloat = 5
            let rowGap: CGFloat = 4.6
            let originX = (bounds.width - (dot * 2 + colGap)) / 2
            let originY = (bounds.height - (dot * 3 + rowGap * 2)) / 2
            for row in 0..<3 {
                for col in 0..<2 {
                    let rect = NSRect(
                        x: originX + CGFloat(col) * (dot + colGap),
                        y: originY + CGFloat(row) * (dot + rowGap),
                        width: dot, height: dot
                    )
                    NSBezierPath(ovalIn: rect).fill()
                }
            }
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    override func mouseDown(with event: NSEvent) {
        downPoint = event.locationInWindow
        isDragging = false
    }

    override func mouseDragged(with event: NSEvent) {
        guard let down = downPoint else { return }
        if !isDragging {
            let dx = event.locationInWindow.x - down.x
            let dy = event.locationInWindow.y - down.y
            guard dx * dx + dy * dy > 9 else { return } // 3px 阈值
            isDragging = true
            NSCursor.closedHand.push()
            onDragPhase?(.began, event)
        } else {
            onDragPhase?(.moved, event)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            onDragPhase?(.ended, event)
            NSCursor.pop()
        }
        downPoint = nil
        isDragging = false
    }
}

/// 从顶部开始排列的容器，让 NSStackView 在滚动视图里正确地从上往下堆
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
