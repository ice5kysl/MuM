import AppKit

/// 关于窗口。
///
/// 为什么不用系统标准 about panel：它的 credits 是一个宽度不可控的滚动文本区，
/// 文案换行听天由命（实测"阅读是目的"被从中间折断），字体层级只有一档，
/// 和 MuM 自己的设计语言完全是两套系统。关于窗口是应用的名片 ——
/// 名片不该穿别人的衣服。
///
/// 元素只留五件，每件都有存在的理由：图标（身份）、名字、版本、
/// 一句话定位、链接行。间距按 4pt 节奏，组内密、组间疏。
final class AboutWindowController: NSWindowController {

    init() {
        let window = AboutWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 368),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        // 与主窗口同一种气质：内容延伸到标题栏底下，不显示标题文字
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.contentView = buildContent()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 在主窗口前方居中弹出
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

        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false

        let name = NSTextField(labelWithString: "MuM")
        name.font = NSFont.systemFont(ofSize: 20, weight: .semibold)
        name.translatesAutoresizingMaskIntoConstraints = false

        // 版本号：数字等宽，第三级颜色 —— 它是参考信息，不是主角
        let version = NSTextField(labelWithString: Self.versionString)
        version.font = NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        version.textColor = MuMDesign.tertiaryText
        version.translatesAutoresizingMaskIntoConstraints = false

        // 名字释义：MuM = Multi-project Markdown（v0.6 定位升级后，
        // 多项目从功能升进了名字）
        let backronym = NSTextField(labelWithString: "Multi-project Markdown")
        backronym.font = NSFont.systemFont(ofSize: 10)
        backronym.textColor = MuMDesign.tertiaryText
        backronym.translatesAutoresizingMaskIntoConstraints = false

        // 定位语必须与 VISION.md 一字不差 —— 它是产品的全部自我认知，
        // 关于窗口没有资格改写它（v0.6：reader → engine，给人也给 agent）。
        // 破折号前后拆成两行：窄窗里整句折行的断点不可控（实测"agent 用"会孤行）
        let tagline = NSTextField(labelWithString: "阅读优先的 Markdown 引擎")
        tagline.font = NSFont.systemFont(ofSize: 12)
        tagline.textColor = MuMDesign.secondaryText
        tagline.translatesAutoresizingMaskIntoConstraints = false

        let audience = NSTextField(labelWithString: "快、原生 —— 给人用，也给 agent 用")
        audience.font = NSFont.systemFont(ofSize: 12)
        audience.textColor = MuMDesign.secondaryText
        audience.translatesAutoresizingMaskIntoConstraints = false

        // 「阅读是目的」保留，它管"给人"那一半
        let motto = NSTextField(labelWithString: "阅读是目的，不是编辑的副产品")
        motto.font = NSFont.systemFont(ofSize: 12)
        motto.textColor = MuMDesign.tertiaryText
        motto.translatesAutoresizingMaskIntoConstraints = false

        // 链接行：GitHub 仓库 · 作者 · 许可证（许可证链到仓库里的 LICENSE）
        let links = NSStackView(views: [
            LinkButton(title: "GitHub", url: "https://github.com/ice5kysl/MuM"),
            separatorDot(),
            LinkButton(title: "ice5kysl", url: "https://github.com/ice5kysl"),
            separatorDot(),
            LinkButton(title: "MIT License", url: "https://github.com/ice5kysl/MuM/blob/main/LICENSE"),
        ])
        links.orientation = .horizontal
        links.alignment = .centerY
        links.spacing = 6
        links.translatesAutoresizingMaskIntoConstraints = false

        content.addSubview(icon)
        content.addSubview(name)
        content.addSubview(backronym)
        content.addSubview(version)
        content.addSubview(tagline)
        content.addSubview(audience)
        content.addSubview(motto)
        content.addSubview(links)
        NSLayoutConstraint.activate([
            icon.topAnchor.constraint(equalTo: content.topAnchor, constant: 56),
            icon.centerXAnchor.constraint(equalTo: content.centerXAnchor),
            icon.widthAnchor.constraint(equalToConstant: 96),
            icon.heightAnchor.constraint(equalToConstant: 96),

            name.topAnchor.constraint(equalTo: icon.bottomAnchor, constant: 16),
            name.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            backronym.topAnchor.constraint(equalTo: name.bottomAnchor, constant: 2),
            backronym.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            version.topAnchor.constraint(equalTo: backronym.bottomAnchor, constant: 4),
            version.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            tagline.topAnchor.constraint(equalTo: version.bottomAnchor, constant: 24),
            tagline.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            audience.topAnchor.constraint(equalTo: tagline.bottomAnchor, constant: 2),
            audience.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            motto.topAnchor.constraint(equalTo: audience.bottomAnchor, constant: 10),
            motto.centerXAnchor.constraint(equalTo: content.centerXAnchor),

            links.topAnchor.constraint(equalTo: motto.bottomAnchor, constant: 12),
            links.centerXAnchor.constraint(equalTo: content.centerXAnchor),
        ])
        return content
    }

    private func separatorDot() -> NSTextField {
        let dot = NSTextField(labelWithString: "·")
        dot.font = NSFont.systemFont(ofSize: 12)
        dot.textColor = MuMDesign.tertiaryText
        return dot
    }

    static var versionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? ""
        let build = info?["CFBundleVersion"] as? String ?? ""
        return build.isEmpty ? version : "\(version) (\(build))"
    }
}

/// 文字链接：悬停时下划线，手型光标，点击用默认浏览器打开。
/// 不用 NSTextField 的 .link 属性 —— 它没有 hover 反馈，
/// 可交互元素 50ms 内必须回应
private final class LinkButton: NSButton {

    private let url: URL
    private let titleText: String

    init(title: String, url: String) {
        self.titleText = title
        self.url = URL(string: url)!
        super.init(frame: .zero)
        isBordered = false
        setButtonType(.momentaryChange)
        target = self
        action = #selector(open)
        attributedTitle = Self.makeTitle(title, underlined: false)
    }

    required init?(coder: NSCoder) {
        fatalError("LinkButton 不走 nib")
    }

    private static func makeTitle(_ title: String, underlined: Bool) -> NSAttributedString {
        var attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: MuMDesign.accent,
        ]
        if underlined {
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return NSAttributedString(string: title, attributes: attributes)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas { removeTrackingArea(area) }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        attributedTitle = Self.makeTitle(titleText, underlined: true)
    }

    override func mouseExited(with event: NSEvent) {
        attributedTitle = Self.makeTitle(titleText, underlined: false)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }

    @objc private func open() {
        NSWorkspace.shared.open(url)
    }
}

/// Esc 关闭
private final class AboutWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}
