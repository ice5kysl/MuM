import AppKit

/// 「在终端中打开」的探测与执行。
///
/// 不认牌子：按优先级探测本机装了的终端（Ghostty → iTerm → 系统终端），
/// 菜单名跟着机器走 —— 没装 Ghostty 的人看到的是自己机器上有的那个。
/// 系统终端（Terminal.app）永远在，所以探测不可能落空。
enum TerminalOpener {

    struct Terminal {
        /// 菜单里的显示名：「在 Ghostty 中打开」/「在 iTerm 中打开」/「在终端中打开」
        let displayName: String
        let bundleID: String
    }

    /// 探测顺序即优先级。系统终端不列进来 —— 它是兜底，不用探。
    private static let candidates: [Terminal] = [
        Terminal(displayName: "Ghostty", bundleID: "com.mitchellh.ghostty"),
        Terminal(displayName: "iTerm", bundleID: "com.googlecode.iterm2"),
    ]

    private static let systemTerminal = Terminal(displayName: "终端", bundleID: "com.apple.Terminal")

    /// 当前机器上该用的终端。`exists` 可注入 —— 探测逻辑（优先级、兜底）不进
    /// 单测就只能在装了特定终端的机器上跑。
    static func detected(
        using exists: (String) -> Bool = { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) != nil }
    ) -> Terminal {
        candidates.first(where: { exists($0.bundleID) }) ?? systemTerminal
    }

    /// 菜单项标题（每次弹菜单现取 —— 终端可能刚装/刚卸）
    static var menuTitle: String { "在 \(detected().displayName) 中打开" }

    /// 菜单图标：终端自己的 app 图标（和「在访达中显示」用 Finder 图标一个道理）
    static var menuIcon: NSImage? {
        let terminal = detected()
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminal.bundleID) else {
            return nil
        }
        let icon = NSWorkspace.shared.icon(forFile: appURL.path)
        icon.size = NSSize(width: 14, height: 14)
        return icon
    }

    /// 在探测到的终端里打开这个目录（新窗口，cwd = 目录）。
    /// Ghostty / iTerm / Terminal 都声明了能开 public.folder，走 LaunchServices 即可。
    ///
    /// 这里**故意**不走 `ExternalOpener`：`open(_:withApplicationAt:configuration:)` 是
    /// 异步重载（completionHandler 默认 nil），本来就是非阻塞的，再包一层反而多余。
    /// 上面那几处 `urlForApplication(withBundleIdentifier:)` 是同步 LS 查询且**必须同步** ——
    /// 菜单标题和图标要在弹菜单那一刻就拿到；它查的是注册表，不是 open 事务，
    /// 与「等 LS 事务梗死」不是同一类风险。
    static func open(_ directory: URL) {
        let terminal = detected()
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminal.bundleID) else {
            return
        }
        NSWorkspace.shared.open(
            [directory],
            withApplicationAt: appURL,
            configuration: NSWorkspace.OpenConfiguration()
        )
    }
}
