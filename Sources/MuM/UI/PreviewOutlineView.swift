import AppKit

/// 文档大纲。按 ⌘⇧O 弹出一个 popover，列出标题，点一条跳过去。
///
/// 做成 popover 而不是常驻侧栏：MuM 的气质是"安静的工具"，而大纲是
/// "长文档里偶尔用一次"的动作。常驻会永久占掉正文宽度，换来的便利不划算。
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
private final class OutlineRowButton: NSButton {

    init(item: MarkdownRenderer.OutlineItem) {
        super.init(frame: .zero)

        isBordered = false
        bezelStyle = .inline
        alignment = .left
        toolTip = item.title

        let size: CGFloat = item.level == 1 ? 12.5 : (item.level == 2 ? 11.5 : 11)
        let weight: NSFont.Weight = item.level == 1 ? .semibold : .regular
        let font = NSFont.systemFont(ofSize: size, weight: weight)
        let color = item.level == 1 ? MuMDesign.primaryText : MuMDesign.secondaryText

        // 缩进走段落样式，不是往标题前面塞空格 —— 空格在截断时会先被吃掉，缩进就没了
        let paragraph = NSMutableParagraphStyle()
        paragraph.firstLineHeadIndent = CGFloat(item.level - 1) * 14 + 10
        paragraph.headIndent = paragraph.firstLineHeadIndent
        paragraph.lineBreakMode = .byTruncatingTail

        attributedTitle = NSAttributedString(string: item.title, attributes: [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ])

        translatesAutoresizingMaskIntoConstraints = false
        heightAnchor.constraint(equalToConstant: item.level == 1 ? 26 : 22).isActive = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
