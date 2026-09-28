import XCTest
@testable import MuM

/// 反馈通道隐私审计（#19，cc 独立层）。
///
/// 分两层：
/// 1. **线上金丝雀**：带唯一标记的真实 POST 到正式端点，收端（dsh 侧 relay）读回
///    原始 JSON 对白名单——wire 级验证「实际发出了什么」，代码说什么不算数。
///    金丝雀只跑一次（发送后记录标记，重复跑会再发——默认跳过，audit 显式开启）。
/// 2. **结构白名单**：payload 编码后的 JSON 键集合必须**恰好**等于
///    {text, contact?, meta{version, os, arch}}——多一个键即红。
///    （kimi 有同向单测；这层是独立复写，防「自己测自己」。）
final class FeedbackPrivacyAuditTests: XCTestCase {

    /// 结构白名单（常跑，进 CI）
    func testPayloadKeysWhitelist() throws {
        let payload = FeedbackSender.Payload(
            text: "审计样本 CC-STRUCT 含 /Users/iceskysl/Code/secret.md 与项目名 mum",
            contact: "audit@local",
            meta: .init(version: "0.8.0", os: "26.3.1", arch: "arm64"))
        let data = try JSONSerialization.jsonObject(with: try XCTUnwrap(payload.jsonBody()))
        let dict = try XCTUnwrap(data as? [String: Any])
        XCTAssertEqual(Set(dict.keys), ["text", "contact", "meta"], "顶层键必须恰好三件")
        let meta = try XCTUnwrap(dict["meta"] as? [String: Any])
        XCTAssertEqual(Set(meta.keys), ["version", "os", "arch"], "meta 键必须恰好三件")
        // 值里不得夹带本地路径（text 本身是用户输入，允许——但 meta 不允许）
        for v in meta.values {
            XCTAssertFalse("\(v)".contains("/Users"), "meta 值不得含本地路径")
        }
        // 空 contact 的形态：字段整个消失，恰好两键
        let bare = FeedbackSender.Payload(text: "t", contact: "  ", meta: payload.meta)
        let d2 = try JSONSerialization.jsonObject(with: try XCTUnwrap(bare.jsonBody())) as! [String: Any]
        XCTAssertEqual(Set(d2.keys), ["text", "meta"], "空白 contact 必须整个字段不出现")
    }

    /// 线上金丝雀（默认跳过；审计时 MUM_FEEDBACK_AUDIT=1 swift test --filter FeedbackPrivacyAudit）
    func testLiveCanaryPost() throws {
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MUM_FEEDBACK_AUDIT"] == "1",
            "默认跳过：线上审计专用（会向正式端点发一条带标记的反馈）")
        let marker = "CC-PRIVACY-AUDIT-\(UUID().uuidString.prefix(8))"
        let payload = FeedbackSender.Payload(
            text: "隐私审计金丝雀 \(marker)：此条由 cc 的 FeedbackPrivacyAuditTests 发出，用于收端字段核对，可忽略。",
            contact: "cc-audit@mum.ice",
            meta: .current)
        let exp = expectation(description: "sent")
        FeedbackSender.send(payload) { outcome in
            print("[audit] outcome=\(outcome) marker=\(marker)")
            if case .sent = outcome {} else {
                XCTFail("线上发送未成功：\(outcome)——端点未通则收端核对无从谈起")
            }
            exp.fulfill()
        }
        wait(for: [exp], timeout: 15)
        // marker 打在 stdout：收端核对时从这里取值
    }
}
