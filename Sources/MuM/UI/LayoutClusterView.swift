import AppKit

/// 常驻的布局开关组，放在底栏中轴偏右。
///
/// 参考 Antigravity / VS Code 的做法：把"哪些模块开着"从一个需要去面板里找的动作，
/// 变成一眼可见、随时可点的状态。每个图标对应一个可折叠的面板，当前可见的用染色底
/// 高亮 —— 这样两栏都收起来时也知道该点哪一个把它们放回来。
///
/// 图标本身就在描述三栏布局：`leadingthird` 是左边第一栏（项目列表），
/// `leadinghalf` 是左边前两栏（含目录树），两个图标在视觉上是嵌套关系，
/// 和它们控制的区域完全对应。
final class LayoutClusterView: NSView {

    var onToggleProjects: (() -> Void)?
    var onToggleTree: (() -> Void)?

    private let projectsButton = LayoutToggleButton(
        symbol: "rectangle.leadingthird.inset.filled",
        tooltip: "显示 / 隐藏项目列表（⌘0）"
    )
    private let treeButton = LayoutToggleButton(
        symbol: "rectangle.leadinghalf.inset.filled",
        tooltip: "显示 / 隐藏目录树（⌥⌘0）"
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        build()
    }

    private func build() {
        projectsButton.onClick = { [weak self] in self?.onToggleProjects?() }
        treeButton.onClick = { [weak self] in self?.onToggleTree?() }

        let stack = NSStackView(views: [projectsButton, treeButton])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.distribution = .fill
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    func update(projectsVisible: Bool, treeVisible: Bool) {
        projectsButton.isOn = projectsVisible
        treeButton.isOn = treeVisible
    }
}

/// 单个布局开关。
///
/// 刻意用朴素 `NSView` 而不是 `NSButton`：`NSButton` 会按 `bezelStyle` 和图标算出一个
/// 约 20.5pt 的固有高度，在 `NSStackView` 里这个尺寸会压过显式的高度约束 ——
/// 按钮比容器高一截、上下各溢出 2pt，染色底看着就"戳出"了状态栏。
/// 重写 `intrinsicContentSize` 也压不住它。纯 NSView 没有这套固有尺寸机制，尺寸完全由约束说了算。
private final class LayoutToggleButton: NSView {

    var isOn = false {
        didSet { refresh() }
    }

    var onClick: (() -> Void)?

    private let iconView = NSImageView()
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    init(symbol: String, tooltip: String) {
        super.init(frame: .zero)

        wantsLayer = true
        layer?.cornerRadius = 4
        layer?.cornerCurve = .continuous
        toolTip = tooltip

        iconView.image = NSImage(systemSymbolName: symbol, accessibilityDescription: tooltip)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        iconView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(iconView)

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 26),
            // 状态栏 26pt，底色只占 16pt，上下各留 5pt 余量
            heightAnchor.constraint(equalToConstant: 16),
            iconView.centerXAnchor.constraint(equalTo: centerXAnchor),
            iconView.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        refresh()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 整块作为一个点击目标，别让图标吃掉事件
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }

    // MARK: - 外观

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

    private func refresh() {
        if isOn {
            layer?.backgroundColor = NSColor.controlAccentColor.withAlphaComponent(0.18).cgColor
            iconView.contentTintColor = .controlAccentColor
        } else if isHovered {
            layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.45).cgColor
            iconView.contentTintColor = MuMDesign.primaryText
        } else {
            layer?.backgroundColor = NSColor.clear.cgColor
            iconView.contentTintColor = MuMDesign.tertiaryText
        }
    }
}
