import AppKit

/// 右侧大纲栏（ToC）。可折叠的常驻导航：列出标题、点击跳转、
/// 「读到哪里」跟随滚动高亮当前节。
///
/// 与 ⌘⇧O 的 popover 分工：popover 管「偶尔跳一下」，这里管「长文档里
/// 一直知道自己读在哪」。行视图与 popover 共用 OutlineRowButton，
/// 两侧观感一致。
final class OutlinePanelController: NSViewController {

    var onSelect: ((Int) -> Void)?

    private var items: [MarkdownRenderer.OutlineItem] = []
    private var rowButtons: [OutlineRowButton] = []
    private var currentIndex: Int?

    private let stack = NSStackView()
    private let emptyLabel = NSTextField(labelWithString: "这篇文档没有标题")
    private let scrollView = NSScrollView()

    override func loadView() {
        // 底色走动态面板色（跟随外观），左缘 1pt 分隔线与正文区隔开
        let background = PaneBackgroundView(color: MuMDesign.paneBackground)
        view = background

        let separator = NSBox()
        separator.boxType = .custom
        separator.borderWidth = 0
        separator.fillColor = MuMDesign.separator
        separator.translatesAutoresizingMaskIntoConstraints = false

        let header = NSTextField(labelWithString: "大纲")
        header.font = NSFont.systemFont(ofSize: 11, weight: .semibold)
        header.textColor = MuMDesign.tertiaryText
        header.translatesAutoresizingMaskIntoConstraints = false

        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 1
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 0, bottom: 8, right: 0)
        stack.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.font = NSFont.systemFont(ofSize: 11)
        emptyLabel.textColor = MuMDesign.tertiaryText
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false
        emptyLabel.isHidden = true

        scrollView.documentView = stack
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(separator)
        view.addSubview(header)
        view.addSubview(scrollView)
        view.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            separator.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            separator.topAnchor.constraint(equalTo: view.topAnchor),
            separator.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            separator.widthAnchor.constraint(equalToConstant: 1),

            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 10),

            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 4),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            emptyLabel.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            emptyLabel.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 24),

            stack.widthAnchor.constraint(equalTo: scrollView.contentView.widthAnchor),
        ])
    }

    /// 每次重排后换入新大纲（location 针对当前渲染结果，旧的不能再用）
    func setOutline(_ items: [MarkdownRenderer.OutlineItem]) {
        self.items = items
        currentIndex = nil
        rowButtons.forEach { $0.removeFromSuperview() }
        rowButtons = items.enumerated().map { index, item in
            let button = OutlineRowButton(item: item)
            button.tag = index
            button.target = self
            button.action = #selector(rowTapped(_:))
            stack.addArrangedSubview(button)
            // 与 popover 同款：stack 是 leading 对齐，行宽必须显式钉满
            button.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
            return button
        }
        emptyLabel.isHidden = !items.isEmpty
    }

    /// 跟随滚动：把「视口顶对应的渲染位置」映射到最近的上文标题并高亮。
    /// 二分，O(log n)，滚动事件里可调。
    func setCurrentLocation(_ renderedOffset: Int) {
        guard !items.isEmpty else { return }
        var lo = 0, hi = items.count - 1
        // 最后一个 location <= renderedOffset 的标题
        if renderedOffset < items[0].location {
            lo = 0
        } else {
            while lo < hi {
                let mid = (lo + hi + 1) / 2
                if items[mid].location <= renderedOffset { lo = mid } else { hi = mid - 1 }
            }
        }
        guard lo != currentIndex else { return }
        if let currentIndex { rowButtons[currentIndex].isCurrent = false }
        currentIndex = lo
        rowButtons[lo].isCurrent = true
        rowButtons[lo].scrollToVisible(rowButtons[lo].bounds)
    }

    @objc private func rowTapped(_ sender: NSButton) {
        guard items.indices.contains(sender.tag) else { return }
        onSelect?(items[sender.tag].location)
    }
}
