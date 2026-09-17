import AppKit

/// 窗口底部的状态栏。
///
/// 三段式，各回答一个问题：
///   · 左：**我在哪** —— 项目 › 文件相对路径
///   · 中：**这篇有多长、在看哪种呈现** —— 字数 / 行数 / 模式
///   · 右：**我开着哪些模块 / 我要调什么** —— 布局开关组 ｜ 设置
///
/// 字数那组放视觉中轴，是因为它随文档变化、是最常被瞟一眼的信息；左右两侧分别是
/// "位置"和"控件"，都是相对静止的。布局开关和设置之间加一条竖线分隔：前者是状态
/// 切换（随时点），后者是入口（偶尔点），性质不同。
final class StatusBarView: NSView {

    let layoutCluster = LayoutClusterView()

    /// 点齿轮 → 系统设置（启动 / 文件 / 缩进 / 系统集成）
    var onShowSettings: ((NSView) -> Void)?
    /// 点 Aa → 显示设置（界面 / 阅读主题 / 排版 / 编辑器显示）
    var onShowDisplaySettings: ((NSView) -> Void)?

    private let leftLabel = NSTextField(labelWithString: "")
    private let detailLabel = NSTextField(labelWithString: "")
    private let settingsButton = NSButton()
    private let displayButton = NSButton()
    private let divider = NSView()
    private let topSeparator = NSBox()

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

        leftLabel.font = MuMDesign.status
        leftLabel.lineBreakMode = .byTruncatingMiddle
        // 双保险：光设 lineBreakMode 不够 —— 下面用 attributedStringValue 赋值时，
        // 富文本自带的段落样式会覆盖 label 上的设置，默认是"按词换行"，
        // 于是很深的文件路径会把标签撑成两行、溢出这条 26pt 的栏。
        leftLabel.usesSingleLineMode = true
        leftLabel.maximumNumberOfLines = 1
        leftLabel.translatesAutoresizingMaskIntoConstraints = false
        leftLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        detailLabel.font = MuMDesign.status
        detailLabel.textColor = MuMDesign.tertiaryText
        detailLabel.alignment = .center
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.translatesAutoresizingMaskIntoConstraints = false
        detailLabel.setContentCompressionResistancePriority(.defaultHigh, for: .horizontal)

        // Aa = 显示设置，齿轮 = 系统设置。两个入口图标放在一起、和左边的布局开关用
        // 竖线隔开：它们都是"设置入口"，但一个改内容长相、一个改应用行为。
        // 用文字 "Aa" 而不是 SF Symbol：`textformat` 在中文本地化下会渲染成「格式」，
        // 和"显示设置"这个含义对不上。
        displayButton.title = "Aa"
        displayButton.font = .systemFont(ofSize: 11, weight: .semibold)
        displayButton.isBordered = false
        displayButton.bezelStyle = .inline
        displayButton.contentTintColor = MuMDesign.secondaryText
        displayButton.target = self
        displayButton.action = #selector(showDisplaySettings)
        displayButton.toolTip = "显示设置：界面、阅读主题、排版"
        displayButton.translatesAutoresizingMaskIntoConstraints = false

        settingsButton.image = NSImage(systemSymbolName: "gearshape", accessibilityDescription: "系统设置")
        settingsButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        settingsButton.isBordered = false
        settingsButton.bezelStyle = .inline
        settingsButton.contentTintColor = MuMDesign.secondaryText
        settingsButton.target = self
        settingsButton.action = #selector(showSettings)
        settingsButton.toolTip = "系统设置：启动、文件、缩进"
        settingsButton.translatesAutoresizingMaskIntoConstraints = false

        divider.wantsLayer = true
        divider.translatesAutoresizingMaskIntoConstraints = false

        layoutCluster.translatesAutoresizingMaskIntoConstraints = false

        topSeparator.boxType = .separator
        topSeparator.translatesAutoresizingMaskIntoConstraints = false

        addSubview(topSeparator)
        addSubview(leftLabel)
        addSubview(detailLabel)
        addSubview(layoutCluster)
        addSubview(divider)
        addSubview(displayButton)
        addSubview(settingsButton)

        NSLayoutConstraint.activate([
            topSeparator.leadingAnchor.constraint(equalTo: leadingAnchor),
            topSeparator.trailingAnchor.constraint(equalTo: trailingAnchor),
            topSeparator.topAnchor.constraint(equalTo: topAnchor),

            // 左：位置
            leftLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 14),
            leftLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            leftLabel.trailingAnchor.constraint(lessThanOrEqualTo: detailLabel.leadingAnchor, constant: -12),

            // 中：字数 · 行数 · 模式
            detailLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            detailLabel.centerYAnchor.constraint(equalTo: centerYAnchor),
            detailLabel.trailingAnchor.constraint(lessThanOrEqualTo: layoutCluster.leadingAnchor, constant: -12),

            // 右：布局开关 ｜ 设置 —— 从右边缘往回排
            settingsButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            settingsButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            settingsButton.widthAnchor.constraint(equalToConstant: 20),
            settingsButton.heightAnchor.constraint(equalToConstant: 20),

            displayButton.trailingAnchor.constraint(equalTo: settingsButton.leadingAnchor, constant: -6),
            displayButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            displayButton.widthAnchor.constraint(equalToConstant: 20),
            displayButton.heightAnchor.constraint(equalToConstant: 20),

            divider.trailingAnchor.constraint(equalTo: displayButton.leadingAnchor, constant: -10),
            divider.centerYAnchor.constraint(equalTo: centerYAnchor),
            divider.widthAnchor.constraint(equalToConstant: 1),
            divider.heightAnchor.constraint(equalToConstant: 12),

            layoutCluster.trailingAnchor.constraint(equalTo: divider.leadingAnchor, constant: -10),
            layoutCluster.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

    }

    /// 和 `PaneBackgroundView` 同样的理由：不要把解析好的 CGColor 缓存起来靠
    /// `viewDidChangeEffectiveAppearance` 重刷 —— 那个回调不保证每个视图都收到，
    /// 实测会出现"面板已经变深、状态栏还是浅的"。`updateLayer()` 每次显示重新解析。
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = MuMDesign.statusBarBackground.cgColor
        divider.layer?.backgroundColor = MuMDesign.separator.cgColor
    }

    @objc private func showSettings() {
        onShowSettings?(settingsButton)
    }

    @objc private func showDisplaySettings() {
        onShowDisplaySettings?(displayButton)
    }



    /// - Parameters:
    ///   - project: 当前项目名
    ///   - location: 文件相对路径
    ///   - detail: 中间信息，例如「2,431 字 · 96 行 · Read」
    func update(project: String?, location: String?, detail: String?) {
        // 段落样式必须写进富文本里：它随 attributedStringValue 一起生效，
        // 单靠 label 自己的 lineBreakMode 会被富文本的默认值盖掉。
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle

        let text = NSMutableAttributedString()
        let base: [NSAttributedString.Key: Any] = [.paragraphStyle: paragraph]

        if let project {
            var attributes = base
            attributes[.font] = NSFont.systemFont(ofSize: 11, weight: .medium)
            attributes[.foregroundColor] = MuMDesign.secondaryText
            text.append(NSAttributedString(string: project, attributes: attributes))
        }

        if let location, !location.isEmpty {
            if text.length > 0 {
                var attributes = base
                attributes[.font] = MuMDesign.status
                attributes[.foregroundColor] = MuMDesign.tertiaryText
                text.append(NSAttributedString(string: "  ›  ", attributes: attributes))
            }
            var attributes = base
            attributes[.font] = MuMDesign.status
            attributes[.foregroundColor] = MuMDesign.tertiaryText
            text.append(NSAttributedString(string: location, attributes: attributes))
        }

        leftLabel.attributedStringValue = text
        detailLabel.stringValue = detail ?? ""
    }
}
