import AppKit

/// 更新提示条：挂在标题栏下缘的窄条（NSTitlebarAccessoryViewController）。
///
/// 为什么不用弹窗：阅读是目的，一次后台检查发现的新版本不配打断阅读。
/// 提示条不抢焦点、不挡正文内容（它把内容往下推一条的高度，而不是盖住），
/// 两个动作都在条上：查看更新（跳 Release 页）/ 忽略此版本（记住，不再烦）。
final class UpdateBannerViewController: NSTitlebarAccessoryViewController {

    /// 点了「忽略此版本」时回调 —— 由调用方负责持久化
    var onIgnore: (() -> Void)?
    /// 提示条从窗口摘下时回调（查看 / 忽略 / × 都会触发）—— 调用方借此清掉强引用
    var onDismiss: (() -> Void)?

    private let update: UpdateChecker.AvailableUpdate

    init(update: UpdateChecker.AvailableUpdate) {
        self.update = update
        super.init(nibName: nil, bundle: nil)
        layoutAttribute = .bottom
    }

    required init?(coder: NSCoder) {
        fatalError("UpdateBannerViewController 不走 nib")
    }

    override func loadView() {
        let container = NSView()
        container.wantsLayer = true
        container.layer?.backgroundColor = MuMDesign.paneBackground.cgColor

        let label = NSTextField(labelWithString: "发现新版本 v\(update.version)")
        label.font = NSFont.systemFont(ofSize: 12)
        label.textColor = MuMDesign.secondaryText

        let viewButton = NSButton(title: "查看更新", target: self, action: #selector(openRelease))
        viewButton.bezelStyle = .inline
        viewButton.controlSize = .small
        viewButton.font = NSFont.systemFont(ofSize: 12)

        let ignoreButton = NSButton(title: "忽略此版本", target: self, action: #selector(ignore))
        ignoreButton.bezelStyle = .inline
        ignoreButton.controlSize = .small
        ignoreButton.font = NSFont.systemFont(ofSize: 12)

        let close = NSButton(title: "", target: self, action: #selector(dismissBanner))
        close.bezelStyle = .inline
        close.controlSize = .small
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭")
        close.imagePosition = .imageOnly

        let stack = NSStackView(views: [label, viewButton, ignoreButton, close])
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 12
        stack.edgeInsets = NSEdgeInsets(top: 4, left: 16, bottom: 4, right: 12)

        let hairline = NSBox()
        hairline.boxType = .separator

        container.addSubview(stack)
        container.addSubview(hairline)
        stack.translatesAutoresizingMaskIntoConstraints = false
        hairline.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: container.topAnchor),
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            stack.bottomAnchor.constraint(equalTo: hairline.topAnchor),

            hairline.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            hairline.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            hairline.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        // fullSizeContentView 的窗口里，标题栏附件的自动布局对 intrinsic 高度
        // 很敏感 —— 显式给定内容高度，避免被压成 0 或把正文挤下去一大块
        view = container
        preferredContentSize = NSSize(width: NSView.noIntrinsicMetric, height: 30)
    }

    @objc private func openRelease() {
        NSWorkspace.shared.open(update.url)
        dismissBanner()
    }

    @objc private func ignore() {
        onIgnore?()
        dismissBanner()
    }

    @objc private func dismissBanner() {
        // 点 × 只是这次不看 —— 下次启动还会再提醒；「忽略此版本」才是记住
        if let window = view.window,
           let index = window.titlebarAccessoryViewControllers.firstIndex(where: { $0 === self }) {
            window.removeTitlebarAccessoryViewController(at: index)
        }
        onDismiss?()
    }
}
