import AppKit

/// 第 2 栏顶部的项目快速切换器。
///
/// 这个位置原来只显示当前项目名，是个只读标签。改成可点的下拉之后，看目录树的时候
/// 想换项目不用回头去第 1 栏 —— 更重要的是，**第 1 栏收起来时也照样能切项目**，
/// 否则项目列表一藏，切换项目就只能靠 ⌘数字 了。
final class ProjectSwitcherControl: NSView {

    var onSelect: ((Int) -> Void)?

    private let iconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let chevron = NSImageView()

    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        wantsLayer = true
        layer?.cornerRadius = 5
        layer?.cornerCurve = .continuous

        iconView.image = NSImage(systemSymbolName: "folder.fill", accessibilityDescription: nil)
        iconView.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 11, weight: .regular)
        iconView.contentTintColor = MuMDesign.secondaryText

        nameLabel.font = MuMDesign.paneTitle
        nameLabel.textColor = MuMDesign.secondaryText
        nameLabel.lineBreakMode = .byTruncatingMiddle
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        chevron.image = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "切换项目")
        chevron.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
        chevron.contentTintColor = MuMDesign.tertiaryText
        chevron.setContentCompressionResistancePriority(.required, for: .horizontal)

        let stack = NSStackView(views: [iconView, nameLabel, chevron])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 6
        stack.translatesAutoresizingMaskIntoConstraints = false

        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 6),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -6),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            heightAnchor.constraint(equalToConstant: 22),
        ])

        toolTip = "切换项目"
    }

    /// 整块作为一个点击目标 —— 否则点到文字上会被 label 吃掉，菜单弹不出来
    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    func update(projectName: String?) {
        nameLabel.stringValue = projectName ?? "没有打开的项目"
        iconView.isHidden = projectName == nil
        chevron.isHidden = projectName == nil
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
        layer?.backgroundColor = isHovered
            ? NSColor.quaternaryLabelColor.withAlphaComponent(0.45).cgColor
            : NSColor.clear.cgColor
    }

    // MARK: - 菜单

    override func mouseDown(with event: NSEvent) {
        let store = WorkspaceStore.shared
        let menu = NSMenu()

        for (index, workspace) in store.workspaces.enumerated() {
            let item = NSMenuItem(
                title: workspace.name,
                action: #selector(pickProject(_:)),
                keyEquivalent: index < 9 ? "\(index + 1)" : ""
            )
            if index < 9 { item.keyEquivalentModifierMask = [.command] }
            item.tag = index
            item.target = self
            item.state = index == store.activeIndex ? .on : .off
            item.image = NSImage(systemSymbolName: "folder", accessibilityDescription: nil)
            menu.addItem(item)
        }

        if store.count > 0 {
            menu.addItem(.separator())
        }

        let open = NSMenuItem(title: "打开项目…", action: #selector(openFolder), keyEquivalent: "o")
        open.keyEquivalentModifierMask = [.command]
        open.target = self
        menu.addItem(open)

        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: bounds.minY - 4), in: self)
    }

    @objc private func pickProject(_ sender: NSMenuItem) {
        onSelect?(sender.tag)
    }

    @objc private func openFolder() {
        WorkspaceStore.shared.promptForFolder()
    }
}
