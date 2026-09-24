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

        // 有直链就一键下载（半自动升级）；没有直链退回跳 Release 页
        let downloadButton = NSButton(
            title: update.downloadURL != nil ? "下载更新" : "查看更新",
            target: self, action: #selector(downloadOrOpenRelease))
        downloadButton.bezelStyle = .inline
        downloadButton.controlSize = .small
        downloadButton.font = NSFont.systemFont(ofSize: 12)
        self.downloadButton = downloadButton

        let notesButton = NSButton(title: "更新说明", target: self, action: #selector(openReleaseNotes))
        notesButton.bezelStyle = .inline
        notesButton.controlSize = .small
        notesButton.font = NSFont.systemFont(ofSize: 12)

        let ignoreButton = NSButton(title: "忽略此版本", target: self, action: #selector(ignore))
        ignoreButton.bezelStyle = .inline
        ignoreButton.controlSize = .small
        ignoreButton.font = NSFont.systemFont(ofSize: 12)

        let close = NSButton(title: "", target: self, action: #selector(dismissBanner))
        close.bezelStyle = .inline
        close.controlSize = .small
        close.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "关闭")
        close.imagePosition = .imageOnly

        let stack = NSStackView(views: [label, downloadButton, notesButton, ignoreButton, close])
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

    @objc private func openReleaseNotes() {
        ExternalOpener.open(update.url)
    }

    private var downloadButton: NSButton?
    private var isDownloading = false

    /// 「下载更新」：下到临时目录 → 挂载安装盘 → 提示拖进应用程序。
    /// 没有直链时这个按钮就是原来的「查看更新」（跳 Release 页）。
    @objc private func downloadOrOpenRelease() {
        guard let downloadURL = update.downloadURL else {
            ExternalOpener.open(update.url)
            dismissBanner()
            return
        }
        guard !isDownloading else { return }
        isDownloading = true
        downloadButton?.isEnabled = false
        downloadButton?.title = "下载中…"

        UpdateDownloader.download(downloadURL, version: update.version) { [weak self] fraction in
            self?.downloadButton?.title = String(format: "下载中 %d%%", Int((fraction * 100).rounded()))
        } completion: { [weak self] result in
            guard let self else { return }
            self.isDownloading = false
            switch result {
            case .success(let dmg):
                self.downloadButton?.title = "已下载"
                UpdateDownloader.mountAndReveal(dmg)
                self.presentInstallHint()
            case .failure(let error):
                self.downloadButton?.isEnabled = true
                self.downloadButton?.title = "下载更新"
                self.presentFailure(error)
            }
        }
    }

    /// 安装盘已挂载：说明最后一步，并给一个「退出 MuM」方便替换
    private func presentInstallHint() {
        let alert = NSAlert()
        alert.messageText = "安装盘已打开"
        alert.informativeText = "把 MuM 拖进「应用程序」文件夹替换旧版即可。退出 MuM 再替换更稳妥。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "退出 MuM")
        alert.addButton(withTitle: "稍后")
        present(alert) { response in
            if response == .alertFirstButtonReturn {
                NSApp.terminate(nil)
            }
        }
    }

    private func presentFailure(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "下载失败"
        alert.informativeText = "\(error.localizedDescription)。也可以点「更新说明」去 Release 页手动下载。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "好")
        present(alert) { _ in }
    }

    private func present(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = view.window {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
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
