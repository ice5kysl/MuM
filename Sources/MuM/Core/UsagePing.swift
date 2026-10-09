import Foundation

/// 每日使用计数（0.8.4「知道自己有没有人在用」）。
///
/// **复用「检查更新」的时机**：启动后打一个 GoatCounter 事件，路径带版本号
/// （`/app-launch/0.8.4`），于是能回答两个问题：**每天有多少人在用**、
/// **他们在用哪个版本**。
///
/// 为什么复用那个时机而不是单独"打卡"：那次网络请求本来就会发出去
/// （以前发给 GitHub Releases，我们看不到统计）。对用户来说这件事的语义是
/// 「检查有没有新版本」——**有回报的**，而不是"App 平白无故打个电话回家"。
///
/// 隐私边界（README 里那段说明就是按这个实现写的，改代码前先读它）：
/// - **没有任何标识** —— 不带设备 ID、用户 ID、安装 ID，连随机 ID 都不生成
/// - **每天最多一次** —— UserDefaults 记「今天已报」，同一天再启动不再发
/// - **不追踪** —— 走站点同一个 GoatCounter：无 cookie、不存 IP（哈希后即弃）、
///   不跨站关联；拿不到"某个人的行为"，只能拿到"某天的总数"
/// - **可以关掉** —— 设置里一个开关，关掉就永不发（`sendsUsagePing`）
/// - **失败静默** —— 断网 / 超时 / 任何错误都不重试、不提示、绝不影响使用
enum UsagePing {

    /// GoatCounter 的计数端点 —— 与 mum.jiker.ai 落地页用的是同一个。
    private static let endpoint = URL(string: "https://mum.goatcounter.com/count")!

    /// 「最后一次上报的日期」（yyyy-MM-dd）存在这个 key 下
    static let lastReportKey = "MuM.lastUsagePingDay"

    /// 事件路径：`/app-launch/<版本>`。版本进路径是为了顺手拿到版本分布，
    /// 在 GoatCounter 里按 `/app-launch` 前缀筛选就是总 DAU。
    static func eventPath(version: String) -> String {
        "/app-launch/\(version)"
    }

    /// 今天要不要报。纯函数，方便测边界（不碰网络、不碰时钟）
    static func shouldReport(today: String, lastReported: String?) -> Bool {
        lastReported != today
    }

    /// UTC 日期串（yyyy-MM-dd）。**用 UTC 而不是本地时区** ——
    /// 否则跨时区旅行 / 夏令时切换会让"今天"来回跳，同一天可能报两次。
    static func dayString(for date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }

    /// 启动时调一次（挂在「启动后检查更新」那个延迟块里，共用同一次网络时机）。
    /// 用户关了、今天已报过、就什么都不做。
    ///
    /// `sender` 可注入：测试要验状态机，但**绝不能真发请求**（会污染统计），
    /// 所以测试一律传 no-op。
    static func reportIfNeeded(settings: MuMSettings,
                               defaults: UserDefaults = .standard,
                               now: Date = Date(),
                               sender: (String) -> Void = { UsagePing.send(version: $0) }) {
        guard settings.sendsUsagePing else { return }

        let today = dayString(for: now)
        let last = defaults.string(forKey: lastReportKey)
        guard shouldReport(today: today, lastReported: last) else { return }

        // **先记账再发**：发失败今天也不重试 —— 这是"失败静默"的一部分，
        // 也避免断网时每次启动都撞一次超时
        defaults.set(today, forKey: lastReportKey)
        sender(UpdateChecker.currentVersion)
    }

    /// 真实网络请求。`session` 可注入，测试拿它验请求形状而不真发。
    static func send(version: String, session: URLSession? = nil) {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "p", value: eventPath(version: version)),
            URLQueryItem(name: "t", value: "MuM launch"),
        ]
        guard let url = components?.url else { return }

        var request = URLRequest(url: url, timeoutInterval: 10)
        request.setValue("MuM/\(version)", forHTTPHeaderField: "User-Agent")

        // ephemeral：不落盘缓存、不带 cookie —— 和更新检查一样，一次纯粹的匿名请求
        let session = session ?? URLSession(configuration: .ephemeral)
        session.dataTask(with: request) { _, _, _ in }.resume()
    }
}
