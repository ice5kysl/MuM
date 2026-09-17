import AppKit

/// 显示设置面板（底栏的 **Aa**）。管的是"内容长什么样"：
/// 界面明暗、阅读主题（纸色）、排版参数、编辑器显示。
///
/// 另一组「应用行为」（启动、文件、缩进、系统集成）在齿轮里，见
/// `SystemSettingsPanelViewController` —— 两者改动频率不同，混在一起
/// 会让常用项被不常用项淹没。
final class SettingsPanelViewController: NSViewController {

    /// 任何一项变化都会回调，调用方负责持久化和应用
    var onChange: ((MuMSettings) -> Void)?

    private var settings: MuMSettings
    private var sliders: [String: SettingsSliderRow] = [:]
    private var toggles: [String: SettingsToggleRow] = [:]
    private var segments: [String: SettingsSegmentedRow] = [:]
    private var themePicker: ReadingThemePicker?

    /// 单栏宽度。两栏 + 栏间距 + 左右内边距 = 面板宽度。
    private static let columnWidth: CGFloat = 196
    private static let columnGap: CGFloat = 18
    private var width: CGFloat { Self.columnWidth }

    init(settings: MuMSettings) {
        self.settings = settings
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 搭建

    override func loadView() {
        view = NSView()

        // 两栏。13 项设置排成一列会有 866pt 高 —— 齿轮在窗口底边，popover 最多往上
        // 展开 870pt，等于顶到屏幕最上沿；一旦封顶就得滚动，于是"编辑器"整组被折叠到
        // 可视区之外，用户会以为设置项凭空消失了（真发生过）。分两栏后总高降到 470pt。
        let left = SettingsControls.column(width: width)
        let right = SettingsControls.column(width: width)

        // —— 左栏：外观 + 编辑器（"界面长什么样"）——
        left.addArrangedSubview(SettingsControls.section("外观", width: width))
        segments["appearance"] = SettingsSegmentedRow(
            title: "界面",
            labels: MuMSettings.Appearance.allCases.map(\.title),
            selected: MuMSettings.Appearance.allCases.firstIndex(of: settings.appearance) ?? 0,
            width: width
        ) { [weak self] index in
            let cases = MuMSettings.Appearance.allCases
            guard cases.indices.contains(index) else { return }
            self?.settings.appearance = cases[index]
            self?.emit()
        }
        left.addArrangedSubview(segments["appearance"]!.view)
        left.addArrangedSubview(themePickerRow())

        left.addArrangedSubview(SettingsControls.section("编辑器", width: width))
        left.addArrangedSubview(slider(
            "editorFontSize", title: "字号",
            value: settings.editorFontSize, range: MuMSettings.editorFontSizeRange, format: "%.0f pt"
        ) { [weak self] value in
            self?.settings.editorFontSize = value
            self?.emit()
        })
        left.addArrangedSubview(toggle(
            "showsLineNumbers", title: "显示行号",
            isOn: settings.showsLineNumbers, hint: "只作用于源码编辑区（Write 模式）"
        ) { [weak self] isOn in
            self?.settings.showsLineNumbers = isOn
            self?.emit()
        })
        left.addArrangedSubview(toggle(
            "highlightsCurrentLine", title: "高亮当前行",
            isOn: settings.highlightsCurrentLine, hint: "只作用于源码编辑区（Write 模式）"
        ) { [weak self] isOn in
            self?.settings.highlightsCurrentLine = isOn
            self?.emit()
        })
        left.addArrangedSubview(toggle(
            "typewriterMode", title: "打字机模式",
            isOn: settings.typewriterMode, hint: "让光标所在行始终停在编辑区中间"
        ) { [weak self] isOn in
            self?.settings.typewriterMode = isOn
            self?.emit()
        })

        // —— 右栏：阅读排版 ——
        right.addArrangedSubview(SettingsControls.section("排版", width: width))
        right.addArrangedSubview(slider(
            "previewFontSize", title: "字号",
            value: settings.previewFontSize, range: MuMSettings.previewFontSizeRange, format: "%.0f pt"
        ) { [weak self] value in
            self?.settings.previewFontSize = value
            self?.emit()
        })
        segments["previewFont"] = SettingsSegmentedRow(
            title: "字体",
            labels: PreviewFont.allCases.map(\.title),
            selected: PreviewFont.allCases.firstIndex(of: settings.previewFont) ?? 0,
            width: width
        ) { [weak self] index in
            let cases = PreviewFont.allCases
            guard cases.indices.contains(index) else { return }
            self?.settings.previewFont = cases[index]
            self?.emit()
        }
        right.addArrangedSubview(segments["previewFont"]!.view)
        right.addArrangedSubview(slider(
            "lineSpacing", title: "行距",
            value: settings.lineSpacing, range: MuMSettings.lineSpacingRange, format: "%.0f pt"
        ) { [weak self] value in
            self?.settings.lineSpacing = value
            self?.emit()
        })
        right.addArrangedSubview(slider(
            "blockSpacing", title: "段间距",
            value: settings.blockSpacing, range: MuMSettings.blockSpacingRange, format: "%.2g×"
        ) { [weak self] value in
            self?.settings.blockSpacing = value
            self?.emit()
        })
        right.addArrangedSubview(slider(
            "letterSpacing", title: "字间距",
            value: settings.letterSpacing, range: MuMSettings.letterSpacingRange, format: "%.1f pt"
        ) { [weak self] value in
            self?.settings.letterSpacing = value
            self?.emit()
        })
        segments["readingWidth"] = SettingsSegmentedRow(
            title: "阅读宽度",
            labels: MarkdownTheme.ReadingWidth.allCases.map(\.title),
            selected: MarkdownTheme.ReadingWidth.allCases.firstIndex(of: settings.readingWidth) ?? 1,
            width: width
        ) { [weak self] index in
            let cases = MarkdownTheme.ReadingWidth.allCases
            guard cases.indices.contains(index) else { return }
            self?.settings.readingWidth = cases[index]
            self?.emit()
        }
        right.addArrangedSubview(segments["readingWidth"]!.view)

        let columns = NSStackView(views: [left, right])
        columns.orientation = .horizontal
        columns.alignment = .top
        columns.spacing = Self.columnGap
        columns.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(columns)

        NSLayoutConstraint.activate([
            columns.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            columns.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            columns.topAnchor.constraint(equalTo: view.topAnchor, constant: 15),
        ])

        // 「恢复默认」横跨两栏放最底下 —— 它是面板级的动作，不属于任何一组
        let reset = NSButton(title: "恢复默认", target: self, action: #selector(resetTapped))
        reset.bezelStyle = .rounded
        reset.controlSize = .small
        reset.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(reset)
        NSLayoutConstraint.activate([
            reset.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            reset.topAnchor.constraint(equalTo: columns.bottomAnchor, constant: 16),
            reset.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -15),
        ])

        view.layoutSubtreeIfNeeded()
        preferredContentSize = NSSize(
            width: Self.columnWidth * 2 + Self.columnGap + 32,
            height: view.fittingSize.height
        )
    }

    /// 阅读主题的一排预览卡片
    private func themePickerRow() -> NSView {
        let titleLabel = NSTextField(labelWithString: "阅读主题")
        titleLabel.font = .systemFont(ofSize: 12)

        let picker = ReadingThemePicker(selected: settings.readingTheme)
        picker.onSelect = { [weak self] theme in
            guard let self else { return }
            self.settings.readingTheme = theme
            self.emit()
        }
        themePicker = picker
        // 显式定宽：这个 picker 的固有宽度只等于"卡片自然宽度之和"，
        // 靠 stack 的 .width 对齐撑不开，卡片会按一个小得多的宽度算出来。
        picker.translatesAutoresizingMaskIntoConstraints = false
        picker.widthAnchor.constraint(equalToConstant: width).isActive = true

        let header = NSStackView(views: [titleLabel, NSView()])
        header.orientation = .horizontal
        header.distribution = .fill

        let row = NSStackView(views: [header, picker])
        row.orientation = .vertical
        row.alignment = .width
        row.spacing = 6
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: width).isActive = true
        return row
    }

    // MARK: - 构件包装（顺手把结果存下来，供「恢复默认」回写）

    private func slider(
        _ key: String, title: String, value: CGFloat,
        range: ClosedRange<CGFloat>, format: String,
        onChange: @escaping (CGFloat) -> Void
    ) -> NSView {
        let row = SettingsSliderRow(
            title: title, value: value, range: range, format: format, width: width, onChange: onChange
        )
        sliders[key] = row
        return row.view
    }

    private func toggle(
        _ key: String, title: String, isOn: Bool, hint: String?,
        onChange: @escaping (Bool) -> Void
    ) -> NSView {
        let row = SettingsToggleRow(title: title, isOn: isOn, hint: hint, width: width, onChange: onChange)
        toggles[key] = row
        return row.view
    }

    private func emit() {
        onChange?(settings)
    }

    @objc private func resetTapped() {
        let defaults = MuMSettings()
        // 只重置本面板管的项，别把系统设置（启动 / 文件 / 缩进）也一起清了
        settings.appearance = defaults.appearance
        settings.readingTheme = defaults.readingTheme
        settings.previewFontSize = defaults.previewFontSize
        settings.previewFont = defaults.previewFont
        settings.lineSpacing = defaults.lineSpacing
        settings.blockSpacing = defaults.blockSpacing
        settings.letterSpacing = defaults.letterSpacing
        settings.readingWidth = defaults.readingWidth
        settings.editorFontSize = defaults.editorFontSize
        settings.showsLineNumbers = defaults.showsLineNumbers
        settings.highlightsCurrentLine = defaults.highlightsCurrentLine
        settings.typewriterMode = defaults.typewriterMode

        sliders["previewFontSize"]?.setValue(settings.previewFontSize)
        sliders["lineSpacing"]?.setValue(settings.lineSpacing)
        sliders["blockSpacing"]?.setValue(settings.blockSpacing)
        sliders["letterSpacing"]?.setValue(settings.letterSpacing)
        sliders["editorFontSize"]?.setValue(settings.editorFontSize)

        segments["appearance"]?.select(MuMSettings.Appearance.allCases.firstIndex(of: settings.appearance) ?? 0)
        segments["previewFont"]?.select(PreviewFont.allCases.firstIndex(of: settings.previewFont) ?? 0)
        segments["readingWidth"]?.select(MarkdownTheme.ReadingWidth.allCases.firstIndex(of: settings.readingWidth) ?? 1)

        toggles["showsLineNumbers"]?.setOn(settings.showsLineNumbers)
        toggles["highlightsCurrentLine"]?.setOn(settings.highlightsCurrentLine)
        toggles["typewriterMode"]?.setOn(settings.typewriterMode)

        themePicker?.select(settings.readingTheme)
        emit()
    }
}
