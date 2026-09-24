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
/// 新增调用点一律走这里。**不要在别处直接调 `NSWorkspace` 的同步方法** ——
/// 这条约束没有编译期闸门，只能靠注释和 review 守住。
enum ExternalOpener {

    /// 打开 URL（网页 / 文档 / 应用 / DMG 挂载）。
    ///
    /// 异步：主线程只负责发起，不等 LS 事务回来。
    static func open(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(url, configuration: configuration) { _, error in
            guard let error else { return }
            // 失败必须留痕：用户点了「用 Safari 打开」而毫无反应，是最难查的那类反馈。
            // 但**不弹模态框** —— 阅读面不该被系统错误挡住；要不要给 UI 提示，交给调用方
            // 按自己的语境决定。
            DispatchQueue.main.async {
                NSLog("[MuM] 打开失败 %@：%@", url.absoluteString, error.localizedDescription)
            }
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
}
