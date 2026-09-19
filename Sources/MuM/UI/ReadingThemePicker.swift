import AppKit

/// 阅读主题选择器：一排卡片，每张用它自己的纸色打底、自己的文字色写一个「Aa」。
///
/// 用真实颜色画卡片而不是列一串名字，是因为"纸"这种东西光看名字想象不出来 ——
/// 暖白到什么程度、暗色压到多深，得看见才知道。
final class ReadingThemePicker: NSView {

    var onSelect: ((ReadingTheme) -> Void)?

    private var cards: [ReadingThemeCard] = []
    private let cardSpacing: CGFloat = 8

    init(selected: ReadingTheme) {
        super.init(frame: .zero)
        build(selected: selected)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build(selected: ReadingTheme) {
        // 2×2 而不是一行四张：一行四张时每张只有 62pt，"跟随外观"四个字会被挤到贴边。
        // 两列之后每张 130pt，色块和名称都舒展了。
        let grid = NSStackView()
        grid.orientation = .vertical
        grid.alignment = .width
        grid.distribution = .fillEqually
        grid.spacing = 8
        grid.translatesAutoresizingMaskIntoConstraints = false

        var rows: [NSStackView] = []
        let themes = ReadingTheme.allCases

        for start in stride(from: 0, to: themes.count, by: 2) {
            let row = NSStackView()
            row.orientation = .horizontal
            row.alignment = .top
            // 用显式宽度而不是靠 .fillEqually：实测在固有宽度只有"卡片自然宽度之和"
            // 的 stack 里，fillEqually 会按那个宽度平分，卡片缩成一半并靠边堆着。
            row.distribution = .fill
            row.spacing = cardSpacing

            for theme in themes[start..<min(start + 2, themes.count)] {
                let card = ReadingThemeCard(theme: theme, isSelected: theme == selected)
                card.onClick = { [weak self] theme in
                    self?.select(theme)
                    self?.onSelect?(theme)
                }
                cards.append(card)
                row.addArrangedSubview(card)
            }

            rows.append(row)
            grid.addArrangedSubview(row)
        }

        addSubview(grid)
        NSLayoutConstraint.activate([
            grid.leadingAnchor.constraint(equalTo: leadingAnchor),
            grid.trailingAnchor.constraint(equalTo: trailingAnchor),
            grid.topAnchor.constraint(equalTo: topAnchor),
            grid.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        // 行宽和卡片宽度都显式约束。要等网格进了层级再激活 ——
        // 之前两者还没有共同祖先，激活会直接抛异常。
        for row in rows {
            row.translatesAutoresizingMaskIntoConstraints = false
            row.widthAnchor.constraint(equalTo: widthAnchor).isActive = true
        }
        for card in cards {
            card.translatesAutoresizingMaskIntoConstraints = false
            card.widthAnchor.constraint(
                equalTo: widthAnchor,
                multiplier: 0.5,
                constant: -cardSpacing / 2
            ).isActive = true
        }
    }

    func select(_ theme: ReadingTheme) {
        for card in cards {
            card.isSelected = (card.theme == theme)
        }
    }

    /// 诊断用（UITestRunner）：模拟点一张主题卡片。
    /// 走和鼠标点击相同的 onClick 路径，而不是只改选中态 —— 否则回调断线测不出来
    func debugClick(_ theme: ReadingTheme) {
        guard let card = cards.first(where: { $0.theme == theme }) else { return }
        card.onClick?(theme)
    }
}

/// 单张主题卡片
private final class ReadingThemeCard: NSView {

    let theme: ReadingTheme
    var onClick: ((ReadingTheme) -> Void)?

    var isSelected: Bool {
        didSet { refreshBorder() }
    }

    private let preview = NSView()
    private let swatchLabel = NSTextField(labelWithString: "Aa")
    private let nameLabel = NSTextField(labelWithString: "")
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    init(theme: ReadingTheme, isSelected: Bool) {
        self.theme = theme
        self.isSelected = isSelected
        super.init(frame: .zero)
        build()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func build() {
        wantsLayer = true

        // 选中框画在色块上而不是整张卡片上 —— 否则名称也被圈进去，
        // 文字压在选中态的底色上，读起来发糊。
        preview.wantsLayer = true
        preview.layer?.borderWidth = 2
        preview.layer?.cornerRadius = 6
        preview.layer?.cornerCurve = .continuous

        preview.layer?.backgroundColor = theme.swatch.background.cgColor
        preview.layer?.cornerRadius = 4
        preview.layer?.borderWidth = 1
        preview.layer?.borderColor = theme.palette.separator.cgColor
        preview.translatesAutoresizingMaskIntoConstraints = false

        swatchLabel.font = .systemFont(ofSize: 19, weight: .medium)
        swatchLabel.textColor = theme.swatch.text
        swatchLabel.alignment = .center
        swatchLabel.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.stringValue = theme.title
        nameLabel.font = .systemFont(ofSize: 10)
        nameLabel.textColor = MuMDesign.secondaryText
        nameLabel.alignment = .center
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.translatesAutoresizingMaskIntoConstraints = false

        preview.addSubview(swatchLabel)
        addSubview(preview)
        addSubview(nameLabel)

        NSLayoutConstraint.activate([
            preview.topAnchor.constraint(equalTo: topAnchor),
            preview.leadingAnchor.constraint(equalTo: leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: trailingAnchor),
            preview.heightAnchor.constraint(equalToConstant: 38),

            swatchLabel.centerXAnchor.constraint(equalTo: preview.centerXAnchor),
            swatchLabel.centerYAnchor.constraint(equalTo: preview.centerYAnchor),

            nameLabel.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 3),
            nameLabel.leadingAnchor.constraint(equalTo: leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: trailingAnchor),
            nameLabel.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        toolTip = theme.title
        refreshBorder()
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        bounds.contains(convert(point, from: superview)) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        onClick?(theme)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        refreshBorder()
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
        refreshBorder()
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        refreshBorder()
    }

    private func refreshBorder() {
        if isSelected {
            preview.layer?.borderColor = NSColor.controlAccentColor.cgColor
        } else if isHovered {
            preview.layer?.borderColor = NSColor.tertiaryLabelColor.cgColor
        } else {
            preview.layer?.borderColor = theme.palette.separator.cgColor
        }
    }
}
