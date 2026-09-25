import XCTest
@testable import MuM

/// 软换行（行尾无两空格的普通换行）按 GitHub 口径渲染成真实换行 ——
/// GFM 文档（尤其中文一行一句、引用块逐行列要点）的作者预期就是分行显示，
/// 渲染成空格会连成一坨（ice 2026-09-25 在 ROADMAP.md 引用块上撞见）。
final class SoftBreakTests: XCTestCase {

    func testSoftBreakRendersAsNewline() {
        let out = MarkdownRenderer(theme: MarkdownTheme(), baseURL: nil)
            .render("第一行\n第二行\n")
        XCTAssertTrue(out.string.contains("第一行\n第二行"), "软换行应渲染成真实换行，实际：\(out.string.debugDescription)")
    }

    func testBlockquoteLinesStaySeparate() {
        let out = MarkdownRenderer(theme: MarkdownTheme(), baseURL: nil)
            .render("> 要点一\n> 要点二\n> 要点三\n")
        XCTAssertTrue(out.string.contains("要点一\n要点二\n要点三"), "引用块逐行应保持分行，实际：\(out.string.debugDescription)")
    }
}
