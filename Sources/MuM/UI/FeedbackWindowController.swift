import AppKit

/// 反馈面板（帮助 → 反馈问题或建议…）。
///
/// 首选应用内直发：POST 到 FeedbackSender.endpoint，不用 GitHub 账号。
/// GitHub 永远兜底 —— 发送失败给链接，通道没配好（404）静默兜过去。
///
/// 面板顶部一行明说会带上什么：隐私不是靠信任，是靠把话说在明处。
final class FeedbackWindowController: NSWindowController {

    private var textView: NSTextView!
    private var contactField: NSTextField!
    private var sendButton: NSButton!
    private var statusLabel: NSTextField!

    init() {
        let window = FeedbackWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 320),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
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
        window.makeFirstResponder(textView)
    }

    // MARK: - 内容

    private func buildContent() -> NSView {
        // 同 About：动态色走 PaneBackgroundView，不存 cgColor 快照（F1）
        let content = PaneBackgroundView(color: MuMDesign.paneBackground)

        let title = NSTextField(labelWithString: "反馈问题或建议")
        title.font = MuMDesign.contentTitle
        title.translatesAutoresizingMaskIntoConstraints = false

        // 带上什么、不带什么，一行说清 —— 这行字就是隐私承诺本身，
        // 改 payload 字段时必须同步改这行（二者在 review 里要一起出现）
        let disclosure = NSTextField(wrappingLabelWithString: "会附上 MuM 版本 / macOS 版本 / 芯片，不带其他任何标识")
        disclosure.font = MuMDesign.status
        disclosure.textColor = MuMDesign.tertiaryText
        disclosure.translatesAutoresizingMaskIntoConstraints = false

        // 反馈内容：多行，必填
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .lineBorder
        scrollView.translatesAutoresizingMaskIntoConstraints = false

        let textView = FeedbackTextView()
        textView.isRichText = false
        textView.font = NSFont.systemFont(ofSize: 13)
        textView.textContainerInset = NSSize(width: 4, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.delegate = self
        scrollView.documentView = textView
        self.textView = textView

        // 联系方式：单行，可空
        let contactField = NSTextField()
        contactField.placeholderString = "联系方式（可选，想收到回复就留一个）"
        contactField.font = NSFont.systemFont(ofSize: 12)
        contactField.translatesAutoresizingMaskIntoConstraints = false
        self.contactField = contactField

        let statusLabel = NSTextField(wrappingLabelWithString: "")
        statusLabel.font = MuMDesign.status
        statusLabel.textColor = MuMDesign.secondaryText
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        self.statusLabel = statusLabel

        // GitHub 兜底入口常驻 —— 它不是错误恢复，是并列的另一条路
        let githubButton = NSButton(title: "改用 GitHub 反馈", target: self, action: #selector(openGitHub))
        githubButton.bezelStyle = .rounded
        githubButton.controlSize = .small
        githubButton.translatesAutoresizingMaskIntoConstraints = false

        let sendButton = NSButton(title: "发送", target: self, action: #selector(sendTapped))
        sendButton.bezelStyle = .rounded
        sendButton.keyEquivalent = "\r" // Return 在文本框里被吃掉了，这个等价键只管 contact 框聚焦时
        sendButton.isEnabled = false
        sendButton.translatesAutoresizingMaskIntoConstraints = false
        self.sendButton = sendButton

        content.addSubview(title)
        content.addSubview(disclosure)
        content.addSubview(scrollView)
        content.addSubview(contactField)
        content.addSubview(statusLabel)
        content.addSubview(githubButton)
        content.addSubview(sendButton)
        NSLayoutConstraint.activate([
            title.topAnchor.constraint(equalTo: content.topAnchor, constant: 24),
            title.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),

            disclosure.topAnchor.constraint(equalTo: title.bottomAnchor, constant: 6),
            disclosure.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            disclosure.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),

            scrollView.topAnchor.constraint(equalTo: disclosure.bottomAnchor, constant: 12),
            scrollView.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            scrollView.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            scrollView.heightAnchor.constraint(equalToConstant: 110),

            contactField.topAnchor.constraint(equalTo: scrollView.bottomAnchor, constant: 10),
            contactField.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            contactField.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),

            statusLabel.topAnchor.constraint(equalTo: contactField.bottomAnchor, constant: 10),
            statusLabel.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            statusLabel.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),

            githubButton.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            githubButton.topAnchor.constraint(equalTo: statusLabel.bottomAnchor, constant: 10),
            githubButton.bottomAnchor.constraint(equalTo: content.bottomAnchor, constant: -16),

            sendButton.trailingAnchor.constraint(equalTo: content.trailingAnchor, constant: -24),
            sendButton.centerYAnchor.constraint(equalTo: githubButton.centerYAnchor),
        ])
        return content
    }

    // MARK: - 发送

    private var feedbackText: String {
        textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @objc func sendTapped() {
        let text = feedbackText
        guard !text.isEmpty else { return }
        sendButton.isEnabled = false
        statusLabel.textColor = MuMDesign.secondaryText
        statusLabel.stringValue = "发送中…"

        let payload = FeedbackSender.Payload(text: text, contact: contactField.stringValue)
        FeedbackSender.send(payload) { [weak self] outcome in
            self?.handle(outcome)
        }
    }

    @MainActor private func handle(_ outcome: FeedbackSender.Outcome) {
        sendButton.isEnabled = !feedbackText.isEmpty
        switch outcome {
        case .sent:
            statusLabel.textColor = MuMDesign.secondaryText
            statusLabel.stringValue = "已收到，谢谢。"
            textView.string = ""
            contactField.stringValue = ""
            sendButton.isEnabled = false

        case .rateLimited(let retryAfter):
            statusLabel.textColor = MuMDesign.secondaryText
            if let retryAfter {
                statusLabel.stringValue = String(format: "发送太频繁，请 %d 秒后再试。", retryAfter)
            } else {
                statusLabel.stringValue = "发送太频繁，请稍后再试。"
            }

        case .channelUnavailable:
            // 通道没配好不是用户的错，也不该让用户看见 —— 静默兜到 GitHub
            openGitHubFallback()
            window?.close()

        case .networkError:
            statusLabel.textColor = .systemRed
            statusLabel.stringValue = "网络不通，没能发出去。请检查网络后重试，或改用 GitHub 反馈。"

        case .serverError(let statusCode):
            statusLabel.textColor = .systemRed
            statusLabel.stringValue = String(format: "反馈服务暂时不可用（%d）。请稍后再试，或改用 GitHub 反馈。", statusCode)
        }
    }

    @objc private func openGitHub() {
        openGitHubFallback()
    }

    /// GitHub 兜底链路和「外部打开」一样走收口（异步，不占主线程等 LS 事务）
    private func openGitHubFallback() {
        if let url = FeedbackSender.githubFallbackURL {
            ExternalOpener.open(url)
        }
    }
}

extension FeedbackWindowController: NSTextViewDelegate {
    /// 空内容禁用发送：必填是「不能为空」，不是「不能为空格」
    func textDidChange(_ notification: Notification) {
        sendButton.isEnabled = !feedbackText.isEmpty
    }
}

/// Return 键留给换行（多行文本框的本分），⌘Return 才是发送
private final class FeedbackTextView: NSTextView {
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        if event.type == .keyDown,
           event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
           event.charactersIgnoringModifiers == "\r" {
            (window?.windowController as? FeedbackWindowController)?.sendTapped()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// Esc 关闭
private final class FeedbackWindow: NSWindow {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}
