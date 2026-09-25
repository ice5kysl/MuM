import AppKit

/// 一切「把 URL / 文件交给系统」的动作都从这里出去。
///
/// **为什么必须收口**：`NSWorkspace.shared.open(_:)` 和
/// `activateFileViewerSelecting(_:)` 都是**同步** API —— 内部走 LaunchServices 的同步
/// XPC（`xpc_connection_send_message_with_reply_sync`）。LS 事务一旦回不来，主线程就在
/// 无限等，界面永久转圈。ice 真机踩到过：两次 sample 间隔 5 分钟、100% 采样同一栈，
/// 而 lsd 是空闲的 —— 是**事务梗死**，不是慢。
///
/// 所以：
/// - **打开**走异步重载 `open(_:configuration:completionHandler:)`，主线程不参与等待
/// - **在访达中显示**没有异步重载，挪到后台队列去调
///
/// **这个文件是唯一的例外**：`scripts/doc-check.sh` 里有一条锚点，禁止 `Sources/`
/// 其它任何地方出现同步的 `NSWorkspace.shared.open(` / `activateFileViewerSelecting(`。
/// 要加新的「交给系统」动作，往这里加一个方法，别绕过去。
///
/// （`urlForApplication(...)` 这类**查询**不在此列：它们要在弹菜单那一刻同步拿到
/// 应用名和图标，查的是注册表而不是 open 事务，不是同一类风险。）
enum ExternalOpener {

    /// 打开 URL（网页 / 文档 / 应用 / DMG 挂载）。
    ///
    /// 异步：主线程只负责发起，不等 LS 事务回来。
    ///
    /// `then` 是**异步化之后才需要的口子**：原来同步调用会一直等到系统那边做完，
    /// 所以调用点后面的代码天然是"打开之后"；现在不会了，凡是有"打开完再做下一步"
    /// 的地方都必须把下一步放进 `then`，而不是写在下一行（更新流程的挂载提示踩过）。
    static func open(_ url: URL, then: (() -> Void)? = nil) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(url, configuration: configuration) { _, error in
            report(error, for: url.absoluteString)
            if let then { DispatchQueue.main.async { then() } }
        }
    }

    /// 用指定应用打开（「在终端中打开」走这条）。
    ///
    /// 同样是异步重载 —— 别因为参数多就退回同步那个。
    static func open(_ urls: [URL], withApplicationAt applicationURL: URL) {
        NSWorkspace.shared.open(
            urls,
            withApplicationAt: applicationURL,
            configuration: NSWorkspace.OpenConfiguration()
        ) { _, error in
            report(error, for: urls.first?.path ?? applicationURL.path)
        }
    }

    /// 在访达中显示并选中。
    ///
    /// `activateFileViewerSelecting` 是同步 XPC 且没有异步重载 —— 唯一的办法是
    /// 不让它待在主线程上。
    static func reveal(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            NSWorkspace.shared.activateFileViewerSelecting(urls)
        }
    }

    /// 失败必须留痕：用户点了「用 Safari 打开」而毫无反应，是最难查的那类反馈。
    /// 但**不弹模态框** —— 阅读面不该被系统错误挡住；要不要给 UI 提示，交给调用方
    /// 按自己的语境决定。
    private static func report(_ error: Error?, for target: String) {
        guard let error else { return }
        DispatchQueue.main.async {
            NSLog("[MuM] 打开失败 %@：%@", target, error.localizedDescription)
        }
    }
}
