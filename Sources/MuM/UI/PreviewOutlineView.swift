import AppKit

/// 文档大纲的弹出层。按 ⌘⇧O 弹出 popover，列出标题，点一条跳过去。
///
/// popover 管「偶尔跳一下」；常驻导航在右侧大纲栏（OutlinePanelController，
/// 可折叠，⌥⌘O）—— 0.7.8 起两者并存，各管各的场景。
final class PreviewOutlineView: NSViewController {

    var onSelect: ((Int) -> Void)?

    private let items: [MarkdownRenderer.OutlineItem]

    init(items: [MarkdownRenderer.OutlineItem]) {
        self.items = items
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false

        for (index, item) in items.enumerated() {
            let button = OutlineRowButton(item: item)
            button.tag = index
            button.target = self
            button.action = #selector(rowTapped(_:))
            stack.addArrangedSubview(button)
            // stack 是 leading 对齐，行不会自动撑满 —— 必须显式钉宽，
            // 否则每行只有按钮自测量的宽度（ice 实测：带缩进段落样式时
            // H2/H3 行被量残，塌到只剩一个字符）
            button.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }

        let scrollView = NSScrollView()
        scrollView.documentView = stack
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])

        // 高度按内容，但封顶 —— 标题几十条的时候不该弹出一个比屏幕还高的框
        let contentHeight = stack.fittingSize.height
        preferredContentSize = NSSize(width: 300, height: min(max(contentHeight, 44), 460))
    }

    @objc private func rowTapped(_ sender: NSButton) {
        guard items.indices.contains(sender.tag) else { return }
        onSelect?(items[sender.tag].location)
    }
}

/// 大纲里的一行。按层级缩进，层级越深字越小越淡。
///
/// 不用 attributedTitle + 段落样式：NSButton 对带缩进段落样式的标题
/// 自测量会算残（H2/H3 行塌到只剩一个字符）。标题交给真正的 NSTextField，
/// 截断、缩进、颜色都归它管；按钮只负责点击和悬停。
/// 大纲 popover 与右侧大纲栏共用（0.7.8 起后者常驻可选）。
final class OutlineRowButton: NSButton {

    private let label: NSTextField
    private let item: MarkdownRenderer.OutlineItem

    /// 「读到这里」高亮：跟随滚动位置，当前节用强调色。默认 false
    var isCurrent = false {
        didSet {
            guard isCurrent != oldValue else { return }
            applyStyle()
        }
    }

    init(item: MarkdownRenderer.OutlineItem) {
        label = NSTextField(labelWithString: item.title)
        self.item = item
        super.init(frame: .zero)

        isBordered = false
        bezelStyle = .inline
        title = ""
        toolTip = item.title

        label.lineBreakMode = .byTruncatingTail
        // 不抢响应：点击和悬停都归按钮
        label.refusesFirstResponder = true
        label.translatesAutoresizingMaskIntoConstraints = false
        addSubview(label)
        applyStyle()

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            // 缩进是版式的一部分，直接算进 label 的左边距
            label.leadingAnchor.constraint(
                equalTo: leadingAnchor, constant: CGFloat(item.level - 1) * 14 + 10),
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

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
