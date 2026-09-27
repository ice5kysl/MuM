import AppKit

/// 应用内反馈通道：把用户的反馈直接 POST 到收集端点，GitHub issue 永远是兜底。
///
/// **隐私边界就在这个文件里**：出去的 JSON 只允许 `text` / `contact` /
/// `meta{version, os, arch}` 四个字段 —— 不带文件名、路径、文档内容、项目名，
/// 也没有任何用户标识。要往 payload 里加字段，先想清楚这条注释还成不成立。
enum FeedbackSender {

    /// 反馈收集端点。全项目唯一 —— 换通道只改这一行。
    static let endpoint = URL(string: "https://in.msg9.io/f/mum")!

    // MARK: - Payload

    /// 自动带上的环境信息，和面板顶部那句「会附上什么」一一对应
    struct Meta: Equatable {
        let version: String
        let os: String
        let arch: String

        static var current: Meta {
            let os = ProcessInfo.processInfo.operatingSystemVersion
            return Meta(
                version: "v\(UpdateChecker.currentVersion)",
                os: "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
                arch: archName
            )
        }

        static var archName: String {
            #if arch(arm64)
            return "Apple Silicon"
            #else
            return "Intel"
            #endif
        }
    }

    struct Payload {
        let text: String
        let contact: String
        let meta: Meta

        init(text: String, contact: String, meta: Meta = .current) {
            self.text = text
            self.contact = contact
            self.meta = meta
        }

        /// 序列化成请求体。字段白名单只在这里出现一次：text / contact / meta。
        /// contact 为空（或全是空白）时整个字段不出现 —— 「可选」就是真的没有。
        func jsonBody() -> Data {
            var body: [String: Any] = [
                "text": text,
                "meta": [
                    "version": meta.version,
                    "os": meta.os,
                    "arch": meta.arch,
                ],
            ]
            let trimmed = contact.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                body["contact"] = trimmed
            }
            // JSONSerialization 而不是 Codable：body 的形状就是白名单本身，
            // 手写字典让"多了哪个字段"在 diff 里一眼可见
            return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
        }
    }

    // MARK: - 结果分类

    enum Outcome: Equatable {
        /// 200：已收到
        case sent
        /// 429：太频繁。Retry-After 头有值就带上秒数
        case rateLimited(retryAfter: Int?)
        /// 404：通道没配好。不给用户看技术性错误，UI 静默兜到 GitHub
        case channelUnavailable
        /// 根本没连上（无网络 / DNS / 超时）
        case networkError
        /// 连上了但服务不可用（502 等其余状态码）
        case serverError(statusCode: Int)
    }

    /// 网络层协议化：测试注入 fake，不真发请求
    protocol Transport {
        func send(_ request: URLRequest, completion: @escaping (Data?, HTTPURLResponse?, Error?) -> Void)
    }

    struct URLSessionTransport: Transport {
        func send(_ request: URLRequest, completion: @escaping (Data?, HTTPURLResponse?, Error?) -> Void) {
            // ephemeral：不落盘缓存、不带 cookie —— 和更新检查同一条匿名规矩
            URLSession(configuration: .ephemeral).dataTask(with: request) { data, response, error in
                completion(data, response as? HTTPURLResponse, error)
            }.resume()
        }
    }

    /// 异步发送。发起和回调都不占主线程等待，完成回调回到主线程。
    static func send(
        _ payload: Payload,
        transport: Transport = URLSessionTransport(),
        completion: @escaping @MainActor (Outcome) -> Void
    ) {
        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = payload.jsonBody()

        transport.send(request) { _, response, error in
            let outcome = classify(statusCode: response?.statusCode, response: response, error: error)
            DispatchQueue.main.async {
                completion(outcome)
            }
        }
    }

    /// 响应 → 结果的映射。提出来做纯函数：四条路径的分叉直接可测。
    static func classify(statusCode: Int?, response: HTTPURLResponse?, error: Error?) -> Outcome {
        if error != nil { return .networkError }
        guard let statusCode else { return .networkError }
        switch statusCode {
        case 200:
            return .sent
        case 404:
            return .channelUnavailable
        case 429:
            let header = response?.value(forHTTPHeaderField: "Retry-After")
            return .rateLimited(retryAfter: header.flatMap(Int.init))
        default:
            return .serverError(statusCode: statusCode)
        }
    }

    // MARK: - GitHub 兜底

    /// GitHub issue 预填页：应用内通道失败 / 没配好时的兜底，也是原来帮助菜单的那条。
    /// issue forms 支持用字段 id 作 URL 参数预填 —— 版本 / macOS / 芯片自动带上。
    static var githubFallbackURL: URL? {
        var components = URLComponents(string: "https://github.com/ice5kysl/MuM/issues/new")!
        let meta = Meta.current
        var queryItems = [URLQueryItem(name: "template", value: "feedback.yml")]
        queryItems.append(URLQueryItem(name: "version", value: meta.version))
        queryItems.append(URLQueryItem(name: "macos", value: "\(meta.os) / \(meta.arch)"))
        components.queryItems = queryItems
        return components.url
    }
}
