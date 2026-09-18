import AppKit

/// 快捷键速查窗口（帮助 → MuM 使用说明）。
///
/// 之前是一个 NSAlert 塞一坨纯文本：警告框的版式是为"一句话+两个按钮"设计的，
/// 拿来排一张参考表，行距、对齐、层级全线失守。参考卡该有参考卡的样子：
/// 快捷键一栏对齐、描述一栏对齐，分组有呼吸，文字三级层级。
final class ShortcutsHelpWindowController: NSWindowController {

    /// （分组名， [（快捷键， 说明）]）。与菜单里的实际键位保持同步 ——
    /// 改键位的人必须同步改这里
    private static let sections: [(String, [(String, String)])] = [
        ("项目", [
            ("⌘O", "打开项目文件夹"),
            ("⌘1 … ⌘9", "切换到第 N 个项目"),
            ("⇧⌘[ / ⇧⌘]", "上一个 / 下一个项目"),
            ("⌥⌘[ / ⌥⌘]", "移动当前项目的位置"),
            ("⇧⌘W", "关闭当前项目"),
        ]),
        ("文件", [
            ("⌘P", "快速打开（按名字模糊搜索）"),
            ("⌘S", "保存"),
            ("⌘R", "从磁盘重新载入"),
            ("⌘W", "关闭当前文件"),
            ("⌘[ / ⌘]", "上一篇 / 下一篇（阅读历史）"),
            ("⇧⌘R", "刷新文件树"),
            ("⇧⌘J", "在访达中显示"),
        ]),
        ("查找", [
            ("⌘F", "在预览中查找"),
            ("⇧⌘F", "全局搜索（跨所有项目）"),
            ("⌘G / ⇧⌘G", "下一处 / 上一处"),
            ("⇧⌘O", "文档大纲"),
        ]),
        ("呈现方式", [
            ("⌥⌘1", "Write — 写源码"),
            ("⌥⌘2", "Read — 阅读"),
            ("⌥⌘3", "Preview — 并排对照"),
        ]),
        ("面板", [
            ("⌘0", "项目列表"),
            ("⌥⌘0", "目录树"),
            ("⌘+ / ⌘-", "预览字号"),
            ("⌃⌘F", "全屏幕"),
        ]),
    ]

    init() {
        let window = HelpWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 640),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false

        super.init(window: window)

        let content = buildContent()
        window.contentView = content
        // 高度由内容决定：算一次 fittingSize，窗口不多一寸空白
        content.layoutSubtreeIfNeeded()
        let fitting = content.fittingSize
        window.setContentSize(NSSize(width: 460, height: fitting.height))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func present(relativeTo parent: NSWindow?) {
        guard let window else { return }
        if let parent {
            let frame = parent.frame
            window.setFrameOrigin(NSPoint(
                x: frame.midX - window.frame.width / 2,
                y: frame.midY - window.frame.height / 2
            ))
        } else {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
    }

    // MARK: - 内容

    private func buildContent() -> NSView {
        let content = NSView()
        content.wantsLayer = true
        content.layer?.backgroundColor = MuMDesign.paneBackground.cgColor

        let title = NSTextField(labelWithString: "快捷键")
        title.font = MuMDesign.contentTitle

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false

        for (index, section) in Self.sections.enumerated() {
            let header = NSTextField(labelWithString: section.0)
            header.font = MuMDesign.paneTitle
            header.textColor = MuMDesign.tertiaryText
            stack.addArrangedSubview(header)
            // 组头离自己的行近一点，离上一组远一点（格式塔接近原则）
            stack.setCustomSpacing(6, after: header)
            for (keys, description) in section.1 {
                stack.addArrangedSubview(makeRow(keys: keys, description: description))
            }
            if index < Self.sections.count - 1 {
                stack.setCustomSpacing(24, after: stack.arrangedSubviews.last!)
            }
        }

        title.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(title)
        content.addSubview(stack)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),

            stack.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -28),
            stack.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -24),
        ])
        return content
    }

    /// 一行：快捷键固定一栏（右对齐、等宽感），说明占余宽。
    /// 键位用主色 —— 速查卡的扫读路径是"找键位 → 看说明"
    private func makeRow(keys: String, description: String) -> NSView {
        let row = NSView()

        let keysLabel = NSTextField(labelWithString: keys)
        keysLabel.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        keysLabel.alignment = .right
        keysLabel.translatesAutoresizingMaskIntoConstraints = false

        let descriptionLabel = NSTextField(labelWithString: description)
        descriptionLabel.font = NSFont.systemFont(ofSize: 12)
        descriptionLabel.textColor = MuMDesign.secondaryText
        descriptionLabel.lineBreakMode = .byTruncatingTail
        descriptionLabel.translatesAutoresizingMaskIntoConstraints = false

        row.addSubview(keysLabel)
        row.addSubview(descriptionLabel)
        NSLayoutConstraint.activate([
            keysLabel.leadingAnchor.constraint(equalTo: row.leadingAnchor),
            keysLabel.widthAnchor.constraint(equalToConstant: 96),
            keysLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            descriptionLabel.leadingAnchor.constraint(equalTo: keysLabel.trailingAnchor, constant: 16),
            descriptionLabel.trailingAnchor.constraint(lessThanOrEqualTo: row.trailingAnchor),
            descriptionLabel.centerYAnchor.constraint(equalTo: row.centerYAnchor),

            row.heightAnchor.constraint(equalToConstant: 18),
        ])
        // stack 是 leading 对齐，行要声明自己撑满
        row.translatesAutoresizingMaskIntoConstraints = false
        return row
    }
}

/// Esc 关闭
private final class HelpWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}
