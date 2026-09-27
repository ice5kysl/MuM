import XCTest
@testable import MuM

/// 反馈通道测试。它守的是两条命：
/// 1. 隐私边界 —— payload 里永远只有 text / contact / meta{version, os, arch}；
/// 2. 错误分类 —— 200/404/429/502/网络错误各走各的路，404 绝不让用户看见。
final class FeedbackSenderTests: XCTestCase {

    private let meta = FeedbackSender.Meta(version: "v9.9.9", os: "macOS 26.0.1", arch: "Apple Silicon")

    private func decode(_ body: Data) -> [String: Any] {
        try! JSONSerialization.jsonObject(with: body) as! [String: Any]
    }

    // MARK: - Payload 构造

    func testPayloadFieldsComplete() {
        let payload = FeedbackSender.Payload(text: "崩溃报告", contact: "me@example.com", meta: meta)
        let json = decode(payload.jsonBody())

        XCTAssertEqual(json["text"] as? String, "崩溃报告")
        XCTAssertEqual(json["contact"] as? String, "me@example.com")
        let metaJSON = json["meta"] as? [String: Any]
        XCTAssertEqual(metaJSON?["version"] as? String, "v9.9.9")
        XCTAssertEqual(metaJSON?["os"] as? String, "macOS 26.0.1")
        XCTAssertEqual(metaJSON?["arch"] as? String, "Apple Silicon")
    }

    func testPayloadOmitsEmptyContact() {
        let blank = FeedbackSender.Payload(text: "建议", contact: "", meta: meta)
        XCTAssertNil(decode(blank.jsonBody())["contact"], "contact 为空时字段不出现")

        let whitespace = FeedbackSender.Payload(text: "建议", contact: "  \n ", meta: meta)
        XCTAssertNil(decode(whitespace.jsonBody())["contact"], "纯空白等同于空")
    }

    func testPayloadKeyWhitelist() {
        // 隐私白名单：顶层只能有 text/contact/meta，meta 里只能有 version/os/arch
        let payload = FeedbackSender.Payload(text: "x", contact: "y", meta: meta)
        let json = decode(payload.jsonBody())
        XCTAssertEqual(Set(json.keys), ["text", "contact", "meta"])
        let metaJSON = json["meta"] as! [String: Any]
        XCTAssertEqual(Set(metaJSON.keys), ["version", "os", "arch"])
    }

    func testPayloadNeverLeaksDocumentContext() {
        // 负向断言：模拟「用户正打开着一份文档」时这些字符串在进程里随处可见，
        // payload 一个字节都不许沾上 —— 文件名、路径、文档内容都不在字段来源里
        let fileName = "家庭账目-2026.md"
        let filePath = "/Users/ice/Private/家庭账目-2026.md"
        let documentContent = "工资卡余额 12800.50"

        let payload = FeedbackSender.Payload(
            text: "阅读体验很好",
            contact: "ice@example.com",
            meta: meta
        )
        let raw = String(data: payload.jsonBody(), encoding: .utf8)!
        XCTAssertFalse(raw.contains(fileName), "payload 不得包含文件名")
        XCTAssertFalse(raw.contains(filePath), "payload 不得包含路径")
        XCTAssertFalse(raw.contains(documentContent), "payload 不得包含文档内容")
        XCTAssertFalse(raw.contains("/Users/"), "payload 不得包含任何用户目录路径")
    }

    // MARK: - 错误分类

    private func httpResponse(_ status: Int, retryAfter: String? = nil) -> HTTPURLResponse {
        var headers: [String: String] = [:]
        if let retryAfter { headers["Retry-After"] = retryAfter }
        return HTTPURLResponse(
            url: FeedbackSender.endpoint, statusCode: status,
            httpVersion: nil, headerFields: headers
        )!
    }

    func testClassify200IsSent() {
        XCTAssertEqual(
            FeedbackSender.classify(statusCode: 200, response: httpResponse(200), error: nil),
            .sent
        )
    }

    func testClassify404IsChannelUnavailable() {
        XCTAssertEqual(
            FeedbackSender.classify(statusCode: 404, response: httpResponse(404), error: nil),
            .channelUnavailable,
            "404 单独一类：UI 静默兜 GitHub，不给用户看技术性错误"
        )
    }

    func testClassify429ReadsRetryAfter() {
        XCTAssertEqual(
            FeedbackSender.classify(statusCode: 429, response: httpResponse(429, retryAfter: "30"), error: nil),
            .rateLimited(retryAfter: 30)
        )
        XCTAssertEqual(
            FeedbackSender.classify(statusCode: 429, response: httpResponse(429), error: nil),
            .rateLimited(retryAfter: nil),
            "没有 Retry-After 头也要能走 429 路径"
        )
    }

    func testClassify502IsServerError() {
        XCTAssertEqual(
            FeedbackSender.classify(statusCode: 502, response: httpResponse(502), error: nil),
            .serverError(statusCode: 502)
        )
    }

    func testClassifyNetworkError() {
        let error = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        XCTAssertEqual(
            FeedbackSender.classify(statusCode: nil, response: nil, error: error),
            .networkError
        )
        // 有错误对象时一律算网络错误，即使碰巧带了个响应
        XCTAssertEqual(
            FeedbackSender.classify(statusCode: 200, response: httpResponse(200), error: error),
            .networkError
        )
    }

    // MARK: - 发送（fake transport 注入，不真发请求）

    private struct FakeTransport: FeedbackSender.Transport {
        let status: Int?
        let retryAfter: String?
        let error: Error?
        let onRequest: (URLRequest) -> Void

        func send(_ request: URLRequest, completion: @escaping (Data?, HTTPURLResponse?, Error?) -> Void) {
            onRequest(request)
            let response = status.map {
                HTTPURLResponse(
                    url: FeedbackSender.endpoint, statusCode: $0, httpVersion: nil,
                    headerFields: retryAfter.map { ["Retry-After": $0] }
                )!
            }
            completion(nil, response, error)
        }
    }

    private func sendAndAwait(
        transport: FeedbackSender.Transport
    ) -> FeedbackSender.Outcome {
        let expectation = expectation(description: "send")
        var outcome: FeedbackSender.Outcome?
        let payload = FeedbackSender.Payload(text: "反馈", contact: "", meta: meta)
        FeedbackSender.send(payload, transport: transport) { result in
            outcome = result
            expectation.fulfill()
        }
        waitForExpectations(timeout: 5)
        return outcome!
    }

    func testSendBuildsPostRequestToEndpoint() {
        var captured: URLRequest?
        let transport = FakeTransport(status: 200, retryAfter: nil, error: nil) { captured = $0 }
        XCTAssertEqual(sendAndAwait(transport: transport), .sent)

        let request = captured!
        XCTAssertEqual(request.url, FeedbackSender.endpoint)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        let json = decode(request.httpBody!)
        XCTAssertEqual(json["text"] as? String, "反馈")
    }

    func testSendMapsEachStatusToItsPath() {
        XCTAssertEqual(sendAndAwait(transport: FakeTransport(status: 404, retryAfter: nil, error: nil) { _ in }), .channelUnavailable)
        XCTAssertEqual(sendAndAwait(transport: FakeTransport(status: 429, retryAfter: "12", error: nil) { _ in }), .rateLimited(retryAfter: 12))
        XCTAssertEqual(sendAndAwait(transport: FakeTransport(status: 502, retryAfter: nil, error: nil) { _ in }), .serverError(statusCode: 502))
        let offline = NSError(domain: NSURLErrorDomain, code: NSURLErrorTimedOut)
        XCTAssertEqual(sendAndAwait(transport: FakeTransport(status: nil, retryAfter: nil, error: offline) { _ in }), .networkError)
    }

    // MARK: - GitHub 兜底

    func testGitHubFallbackURLPrefillsMeta() {
        let url = FeedbackSender.githubFallbackURL!
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        XCTAssertEqual(components.host, "github.com")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["template"], "feedback.yml")
        XCTAssertFalse(items["version"]?.isEmpty ?? true, "版本预填")
        XCTAssertTrue(items["macos"]?.contains("macOS") ?? false, "macOS / 芯片预填")
    }
}
