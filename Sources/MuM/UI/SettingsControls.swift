import AppKit

/// 设置面板里的一行。两个面板（显示设置 / 系统设置）共用这些构件，
/// 否则同一套「标题 + 滑块」「标题 + 分段控件」要写两遍。
enum SettingsControls {

    /// 分组标题。前面配一条细分隔线，让"这一组从哪开始"一眼可见 ——
    /// 只靠字号和颜色区分，一整列控制项看下来会糊成一片。
    static func section(_ text: String, width: CGFloat) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = MuMDesign.secondaryText

        let line = NSBox()
        line.boxType = .separator
        line.translatesAutoresizingMaskIntoConstraints = false
        line.widthAnchor.constraint(equalToConstant: width).isActive = true

        let group = NSStackView(views: [line, label])
        group.orientation = .vertical
        group.alignment = .leading
        group.spacing = 10
        group.translatesAutoresizingMaskIntoConstraints = false
        group.widthAnchor.constraint(equalToConstant: width).isActive = true
        return group
    }

    /// 一栏：竖向排列，固定宽度
    static func column(width: CGFloat) -> NSStackView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 13
        stack.translatesAutoresizingMaskIntoConstraints = false
        stack.widthAnchor.constraint(equalToConstant: width).isActive = true
        return stack
    }

    /// 竖向两件套（标题行 + 控件）
    static func vertical(width: CGFloat, _ views: [NSView]) -> NSStackView {
        let row = NSStackView(views: views)
        row.orientation = .vertical
        row.alignment = .width
        row.spacing = 4
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: width).isActive = true
        return row
    }
}

/// 「标题 —— 当前值」+ 滑块。值的变化由构件自己更新显示，调用方只管收值。
final class SettingsSliderRow {
    let view: NSView
    let slider: NSSlider

    private let valueLabel: NSTextField
    private let format: String

    init(
        title: String,
        value: CGFloat,
        range: ClosedRange<CGFloat>,
        format: String,
        width: CGFloat,
        onChange: @escaping (CGFloat) -> Void
    ) {
        self.format = format

        valueLabel = NSTextField(labelWithString: String(format: format, Double(value)))
        valueLabel.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        valueLabel.textColor = MuMDesign.tertiaryText
        valueLabel.alignment = .right

        slider = NSSlider(
            value: Double(value),
            minValue: Double(range.lowerBound),
            maxValue: Double(range.upperBound),
            target: nil,
            action: nil
        )
        slider.isContinuous = true
        slider.controlSize = .small

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12)
        let header = NSStackView(views: [titleLabel, NSView(), valueLabel])
        header.orientation = .horizontal
        header.distribution = .fill

        view = SettingsControls.vertical(width: width, [header, slider])

        slider.target = self
        slider.action = #selector(changed)
        self.onChange = onChange
    }

    /// 外部改值（比如「恢复默认」）时，滑块和数值文字都要跟上
    func setValue(_ value: CGFloat) {
        slider.doubleValue = Double(value)
        valueLabel.stringValue = String(format: format, Double(value))
    }

    private var onChange: ((CGFloat) -> Void)?

    @objc private func changed() {
        valueLabel.stringValue = String(format: format, slider.doubleValue)
        onChange?(CGFloat(slider.doubleValue))
    }
}

/// 「标题」+ 分段控件。界面 / 字体 / 阅读宽度 / 启动模式共用。
final class SettingsSegmentedRow {
    let view: NSView
    let control: NSSegmentedControl

    init(
        title: String,
        labels: [String],
        selected: Int,
        width: CGFloat,
        onChange: @escaping (Int) -> Void
    ) {
        control = NSSegmentedControl(
            labels: labels,
            trackingMode: .selectOne,
            target: nil,
            action: nil
        )
        control.selectedSegment = selected
        control.segmentStyle = .rounded
        control.segmentDistribution = .fillEqually

        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12)
        let header = NSStackView(views: [titleLabel, NSView()])
        header.orientation = .horizontal
        header.distribution = .fill

        view = SettingsControls.vertical(width: width, [header, control])

        control.target = self
        control.action = #selector(changed)
        self.onChange = onChange
    }

    func select(_ index: Int) {
        control.selectedSegment = index
    }

    private var onChange: ((Int) -> Void)?

    @objc private func changed() {
        onChange?(control.selectedSegment)
    }
}

/// 复选框，可带一行灰色副标题说明作用范围
final class SettingsToggleRow {
    let view: NSView
    let button: NSButton

    init(
        title: String,
        isOn: Bool,
        hint: String? = nil,
        width: CGFloat,
        onChange: @escaping (Bool) -> Void
    ) {
        button = NSButton(checkboxWithTitle: title, target: nil, action: nil)
        button.state = isOn ? .on : .off
        button.font = .systemFont(ofSize: 12)
        button.translatesAutoresizingMaskIntoConstraints = false
        button.widthAnchor.constraint(equalToConstant: width).isActive = true

        guard let hint else {
            view = button
            self.onChange = onChange
            button.target = self
            button.action = #selector(changed)
            return
        }

        let hintLabel = NSTextField(labelWithString: hint)
        hintLabel.font = .systemFont(ofSize: 10.5)
        hintLabel.textColor = MuMDesign.tertiaryText
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        let row = NSStackView(views: [button, hintLabel])
        row.orientation = .vertical
        row.alignment = .leading
        row.spacing = 1
        row.translatesAutoresizingMaskIntoConstraints = false
        row.widthAnchor.constraint(equalToConstant: width).isActive = true
        view = row

        self.onChange = onChange
        button.target = self
        button.action = #selector(changed)
    }

    func setOn(_ isOn: Bool) {
        button.state = isOn ? .on : .off
    }

    private var onChange: ((Bool) -> Void)?

    @objc private func changed() {
        onChange?(button.state == .on)
    }
}
