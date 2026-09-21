import AppKit

/// 版本更新检查。更新源 = GitHub Releases 的公开 API，不需要后台、不需要 token：
/// `GET /repos/ice5kysl/MuM/releases/latest` 匿名请求，不带任何用户标识 ——
/// 和"没有账号、没有上报"的气质一致。
///
/// 只提醒，不自动下载：DMG 走签名公证链路，跳 Release 页让用户自己下最干净。
enum UpdateChecker {

    struct AvailableUpdate {
        /// 不带 `v` 前缀的版本号，如 "0.7.1"
        let version: String
        /// Release 页面
        let url: URL
        /// 安装包直链（DMG 优先）。nil 表示 Release 里没有可下载资产，退回跳页面
        let downloadURL: URL?
        /// 安装包字节数（进度条分母），未知为 nil
        let downloadSize: Int?
    }

    enum Result {
        case upToDate
        case available(AvailableUpdate)
        /// 网络 / 解析失败。静默检查时吞掉，手动检查时明说
        case failed
    }

    static var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// 异步检查，完成回调回到主线程。10 秒超时，不挡任何东西。
    static func check(completion: @escaping @MainActor (Result) -> Void) {
        var request = URLRequest(
            url: URL(string: "https://api.github.com/repos/ice5kysl/MuM/releases/latest")!,
            timeoutInterval: 10
        )
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("MuM/\(currentVersion)", forHTTPHeaderField: "User-Agent")

        // ephemeral：不落盘缓存、不带 cookie —— 一次纯粹的匿名查询
        URLSession(configuration: .ephemeral).dataTask(with: request) { data, response, error in
            let result: Result
            defer {
                DispatchQueue.main.async { completion(result) }
            }
            guard error == nil,
                  let data,
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String,
                  let pageURL = (json["html_url"] as? String).flatMap(URL.init(string:))
            else {
                result = .failed
                return
            }
            let latest = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
            let asset = Self.pickAsset(from: json)
            result = isNewer(latest, than: currentVersion)
                ? .available(AvailableUpdate(version: latest, url: pageURL,
                                             downloadURL: asset?.url, downloadSize: asset?.size))
                : .upToDate
        }.resume()
    }

    /// 从 Release JSON 的 assets 里挑安装包：DMG 优先，ZIP 兜底。
    /// 提出来做纯函数 —— 资产选择的对错直接可测，不用发网络请求。
    static func pickAsset(from json: [String: Any]) -> (url: URL, size: Int?)? {
        guard let assets = json["assets"] as? [[String: Any]] else { return nil }
        func asset(matchingSuffix suffix: String) -> (url: URL, size: Int?)? {
            for asset in assets {
                guard let name = asset["name"] as? String,
                      name.lowercased().hasSuffix(suffix),
                      let link = asset["browser_download_url"] as? String,
                      let url = URL(string: link) else { continue }
                return (url, asset["size"] as? Int)
            }
            return nil
        }
        return asset(matchingSuffix: ".dmg") ?? asset(matchingSuffix: ".zip")
    }

    /// 语义化版本比较：逐段数值比，"0.7.1" > "0.7.0"。段数不齐时缺的按 0 算。
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0
            let y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
