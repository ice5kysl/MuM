import XCTest
import PDFKit
@testable import MuM

/// 行内 HTML 白名单渲染：<small>/<mark>/<sup> 等配对标签折回样式并吞掉，
/// 白名单外的标签仍按原始文本输出（README/口语稿里常见的 <small> 要点批注场景）。
final class InlineHTMLTests: XCTestCase {

    private let renderer = MarkdownRenderer(theme: MarkdownTheme(), baseURL: nil)
    private let theme = MarkdownTheme()

    private func attribute<T>(_ key: NSAttributedString.Key, contains needle: String, in text: NSAttributedString) -> T? {
        let range = (text.string as NSString).range(of: needle)
        guard range.location != NSNotFound else { return nil }
        return text.attribute(key, at: range.location, effectiveRange: nil) as? T
    }

    func testSmallTagShrinksAndIsHidden() {
        let out = renderer.render("<small>要点批注</small>\n")
        XCTAssertFalse(out.string.contains("<small"), "开标签不应出现在成文里")
        XCTAssertFalse(out.string.contains("</small"), "闭标签不应出现在成文里")
        let font: NSFont? = attribute(.font, contains: "要点批注", in: out)
        XCTAssertNotNil(font)
        XCTAssertLessThan(font?.pointSize ?? .infinity, theme.bodyFont.pointSize,
                          "<small> 内容字号应小于正文")
    }

    func testBoldAndMarkTags() {
        let out = renderer.render("<b>加粗</b> 和 <mark>高亮</mark>\n")
        XCTAssertFalse(out.string.contains("<mark"))
        let boldFont: NSFont? = attribute(.font, contains: "加粗", in: out)
        XCTAssertEqual(boldFont?.pointSize, theme.boldFont.pointSize)
        let background: NSColor? = attribute(.backgroundColor, contains: "高亮", in: out)
        XCTAssertNotNil(background, "<mark> 内容应有高亮底色")
    }

    func testSuperscriptShiftsBaseline() {
        let out = renderer.render("面积 m<sup>2</sup>\n")
        let shift: NSNumber? = attribute(.baselineOffset, contains: "2", in: out)
        XCTAssertNotNil(shift)
        XCTAssertGreaterThan(shift?.doubleValue ?? 0, 0, "<sup> 应抬高基线")
        let font: NSFont? = attribute(.font, contains: "2", in: out)
        XCTAssertLessThan(font?.pointSize ?? .infinity, theme.bodyFont.pointSize)
    }

    func testUnknownTagStaysAsRawText() {
        let out = renderer.render("<blink>闪</blink>\n")
        XCTAssertTrue(out.string.contains("<blink>"),
                      "白名单外的标签保持原始文本输出（README 里贴 HTML 片段的场景）")
    }

    func testSpanIsSwallowedWithoutStyleChange() {
        // <span> 无语义：吞掉标签、不改样式（dsh 验收 F2：行为合理但要有测试钉住）
        let out = renderer.render("<span class=\"hl\">关键词</span>\n")
        XCTAssertFalse(out.string.contains("<span"), "span 标签被吞掉")
        XCTAssertTrue(out.string.contains("关键词"))
        let font: NSFont? = attribute(.font, contains: "关键词", in: out)
        XCTAssertEqual(font?.pointSize, theme.bodyFont.pointSize, "span 不改字号")
        let background: NSColor? = attribute(.backgroundColor, contains: "关键词", in: out)
        XCTAssertNil(background, "span 不加底色")
    }

    func testUnmatchedCloseTagIsSwallowed() {
        let out = renderer.render("</small>正文\n")
        XCTAssertFalse(out.string.contains("</small"))
        let font: NSFont? = attribute(.font, contains: "正文", in: out)
        XCTAssertEqual(font?.pointSize, theme.bodyFont.pointSize,
                       "配不上对的闭标签只吞掉、不影响后续样式")
    }

    func testMismatchedCloseDoesNotPopOtherTag() {
        // <small> 未闭合时被 </em> 错关：small 的缩放应保留到自己的闭标签
        let out = renderer.render("<small>甲</em>乙</small>丙\n")
        let body = theme.bodyFont.pointSize
        let b: NSFont? = attribute(.font, contains: "乙", in: out)
        let c: NSFont? = attribute(.font, contains: "丙", in: out)
        XCTAssertLessThan(b?.pointSize ?? .infinity, body, "错关 </em> 不应提前结束 <small>")
        XCTAssertEqual(c?.pointSize, body, "</small> 之后恢复正文字号")
    }

    func testBreakTagEmitsNewline() {
        let out = renderer.render("第一行<br>第二行\n")
        XCTAssertTrue(out.string.contains("第一行\n第二行") || out.string.contains("第一行\n第二行".replacingOccurrences(of: "\n", with: "\n")),
                      "<br> 应输出换行")
        XCTAssertFalse(out.string.contains("<br"))
    }

    // MARK: - 块级 HTML

    func testPageBreakDivIsHidden() {
        let out = renderer.render("上文\n\n<div style=\"break-after: page; page-break-after: always;\"></div>\n\n下文\n")
        XCTAssertFalse(out.string.contains("break-after"), "分页空 div 不应出现在成文里")
        XCTAssertTrue(out.string.contains("上文"))
        XCTAssertTrue(out.string.contains("下文"))
    }

    func testCommentBlockIsHidden() {
        let out = renderer.render("上文\n\n<!-- ↓↓↓ 第 2 页从这里开始 ↓↓↓ -->\n\n下文\n")
        XCTAssertFalse(out.string.contains("<!--"), "HTML 注释不应出现在成文里")
        XCTAssertFalse(out.string.contains("第 2 页从这里开始"))
    }

    func testHTMLBlockWithRealContentStaysRaw() {
        let out = renderer.render("<div>这段文字是内容</div>\n")
        XCTAssertTrue(out.string.contains("<div>"),
                      "带真实内容的 HTML 片段仍按原文显示（贴片段做笔记的场景）")
        XCTAssertTrue(out.string.contains("这段文字是内容"))
    }

    // MARK: - 分页指令

    func testPageBreakLocationsRecorded() {
        let markdown = "第一节\n\n<div style=\"break-after: page; page-break-after: always;\"></div>\n\n第二节\n\n<!-- 注释不是分页 -->\n\n第三节\n"
        _ = renderer.render(markdown)
        XCTAssertEqual(renderer.pageBreakLocations.count, 1,
                       "只有分页 div 记位置，注释和普通隐藏块不记")
        let location = renderer.pageBreakLocations[0]
        XCTAssertGreaterThan(location, 0)
    }

    func testPageBreakVariantsMatched() {
        XCTAssertTrue(MarkdownRenderer.isPageBreakHTML("<div style=\"break-after: page;\"></div>"))
        XCTAssertTrue(MarkdownRenderer.isPageBreakHTML("<div style=\"page-break-after: always;\"></div>"))
        XCTAssertTrue(MarkdownRenderer.isPageBreakHTML("<div style=\"page-break-before:always\"></div>"))
        XCTAssertTrue(MarkdownRenderer.isPageBreakHTML("<p style=\"BREAK-AFTER: PAGE\"></p>"))
        XCTAssertFalse(MarkdownRenderer.isPageBreakHTML("<!-- 普通注释 -->"))
        XCTAssertFalse(MarkdownRenderer.isPageBreakHTML("<div style=\"color: red;\">文字</div>"))
    }

    /// 分页指令导出 PDF 时真正分页：带一个分页点的短文档出 2 页，
    /// 同样内容去掉指令只有 1 页（自然排版装得下）。
    func testPDFHonorsPageBreak() throws {
        let withBreak = "第一节\n\n<div style=\"page-break-after: always;\"></div>\n\n第二节\n"
        let withoutBreak = "第一节\n\n第二节\n"
        var options = DocumentRenderer.Options()
        options.dark = false

        let broken = DocumentRenderer.render(text: withBreak, kind: .markdown, baseURL: nil, options: options)
        let plain = DocumentRenderer.render(text: withoutBreak, kind: .markdown, baseURL: nil, options: options)

        let brokenPDF = try XCTUnwrap(DocumentRenderer.pdf(broken, options: options))
        let plainPDF = try XCTUnwrap(DocumentRenderer.pdf(plain, options: options))

        XCTAssertEqual(PDFDocument(data: brokenPDF)?.pageCount, 2,
                       "一个分页指令 → 强制 2 页（自然排版 1 页就装得下）")
        XCTAssertEqual(PDFDocument(data: plainPDF)?.pageCount, 1,
                       "没有指令的对照组保持 1 页")
    }
}
