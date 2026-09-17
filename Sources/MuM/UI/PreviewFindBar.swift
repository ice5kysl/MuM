import AppKit

/// 预览区的查找条。按 ⌘F 从内容区顶部滑出，Esc 关闭。
///
/// 做成内容区自己的一条，而不是独立浮层：MuM 的气质是"安静的工具"，
/// 查找是阅读的辅助动作，不该独占一个窗口或遮住正文。
final class PreviewFindBar: NSView {

    var onQueryChanged: ((String) -> Void)?
    var onNext: (() -> Void)?
    var onPrevious: (() -> Void)?
    var onClose: (() -> Void)?

    private let searchField = NSSearchField()
    private let countLabel = NSTextField(labelWithString: "")
    private let previousButton = NSButton()
    private let nextButton = NSButton()
    private let closeButton = NSButton()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
    }

    private func build() {
        wantsLayer = true
        layer?.backgroundColor = MuMDesign.paneBackground.cgColor

        searchField.placeholderString = "在文档中查找"
        searchField.font = .systemFont(ofSize: 12)
        searchField.target = self
        searchField.action = #selector(queryChanged)
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.translatesAutoresizingMaskIntoConstraints = false

        countLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        countLabel.textColor = MuMDesign.tertiaryText
        countLabel.alignment = .right
        countLabel.translatesAutoresizingMaskIntoConstraints = false

        configure(previousButton, symbol: "chevron.up", tooltip: "上一处（⇧⏎）", action: #selector(goPrevious))
        configure(nextButton, symbol: "chevron.down", tooltip: "下一处（⏎）", action: #selector(goNext))
        configure(closeButton, symbol: "xmark", tooltip: "关闭（Esc）", action: #selector(close))

        let stack = NSStackView(views: [searchField, countLabel, previousButton, nextButton, closeButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            searchField.widthAnchor.constraint(greaterThanOrEqualToConstant: 200),
            countLabel.widthAnchor.constraint(equalToConstant: 62),
        ])
    }

    private func configure(_ button: NSButton, symbol: String, tooltip: String, action: Selector) {
        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        button.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        button.isBordered = false
        button.bezelStyle = .inline
        button.contentTintColor = MuMDesign.secondaryText
        button.toolTip = tooltip
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: 22).isActive = true
    }

    // MARK: - 对外

    var query: String { searchField.stringValue }

    /// 诊断用：程序化填入查询词
    func setQuery(_ text: String) {
        searchField.stringValue = text
    }

    func focus() {
        window?.makeFirstResponder(searchField)
        searchField.currentEditor()?.selectAll(nil)
    }

    /// - Parameters:
    ///   - current: 当前第几处（1 起算；0 表示没有匹配）
    ///   - total: 共几处
    func update(current: Int, total: Int) {
        countLabel.stringValue = total == 0 ? "无匹配" : "\(current) / \(total)"
        previousButton.isEnabled = total > 0
        nextButton.isEnabled = total > 0
    }

    @objc private func queryChanged() { onQueryChanged?(searchField.stringValue) }
    @objc private func goNext() { onNext?() }
    @objc private func goPrevious() { onPrevious?() }
    @objc private func close() { onClose?() }

    /// ⏎ 下一处、⇧⏎ 上一处。搜索框抢走焦点时也要能用。
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.keyCode == 36 || event.keyCode == 76 else { return super.performKeyEquivalent(with: event) }
        if event.modifierFlags.contains(.shift) { onPrevious?() } else { onNext?() }
        return true
    }

    /// Esc 关闭
    override func cancelOperation(_ sender: Any?) {
        onClose?()
    }
}
