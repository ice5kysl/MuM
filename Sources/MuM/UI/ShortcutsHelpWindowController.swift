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
        (L10n.t("项目"), [
            ("⌘O", L10n.t("打开项目文件夹")),
            ("⌘1 … ⌘9", L10n.t("切换到第 N 个项目")),
            ("⇧⌘[ / ⇧⌘]", L10n.t("上一个 / 下一个项目")),
            ("⌥⌘[ / ⌥⌘]", L10n.t("移动当前项目的位置")),
            ("⇧⌘W", L10n.t("关闭当前项目")),
        ]),
        (L10n.t("文件"), [
            ("⌘P", L10n.t("快速打开（按名字模糊搜索）")),
            ("⌘S", L10n.t("保存")),
            ("⌘R", L10n.t("从磁盘重新载入")),
            ("⌘W", L10n.t("关闭当前文件")),
            ("⌘[ / ⌘]", L10n.t("上一篇 / 下一篇（阅读历史）")),
            ("⇧⌘R", L10n.t("刷新文件树")),
            ("⇧⌘J", L10n.t("在访达中显示")),
        ]),
        (L10n.t("查找"), [
            ("⌘F", L10n.t("在预览中查找")),
            ("⇧⌘F", L10n.t("全局搜索（跨所有项目）")),
            ("⌘G / ⇧⌘G", L10n.t("下一处 / 上一处")),
            ("⇧⌘O", L10n.t("大纲栏")),
        ]),
        (L10n.t("呈现方式"), [
            ("⌥⌘1", L10n.t("Write — 写源码")),
            ("⌥⌘2", L10n.t("Read — 阅读")),
            ("⌥⌘3", L10n.t("Preview — 并排对照")),
        ]),
        (L10n.t("面板"), [
            ("⌘0", L10n.t("项目列表")),
            ("⌥⌘0", L10n.t("目录树")),
            ("⌘+ / ⌘-", L10n.t("预览字号")),
            ("⌃⌘F", L10n.t("全屏幕")),
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
        // 同 About：动态色走 PaneBackgroundView，不存 cgColor 快照（F1）
        let content = PaneBackgroundView(color: MuMDesign.paneBackground)

        let title = NSTextField(labelWithString: L10n.t("快捷键"))
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
    /// 键位用主色 —— 速查卡的扫读路径是")找键位 → 看说明"
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
