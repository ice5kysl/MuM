import XCTest
@testable import MuM

/// YAML frontmatter（`---` 包着的元数据头）是元数据不是内容，阅读时隐藏
/// （Typora/Obsidian 同款）。剥离会让后续内容的源码行号整体偏移，
/// 滚动联动的锚点必须加回这个偏移，否则对着编辑器行号就漂了。
final class FrontmatterTests: XCTestCase {

    func testFrontmatterHidden() {
        let r = MarkdownRenderer(theme: MarkdownTheme(), baseURL: nil)
        let rendered = r.render("---\nname: live-video\ndescription: 测试\n---\n# 正文标题\n\n正文第一段。\n")
        XCTAssertFalse(rendered.string.contains("name:"), "frontmatter 字段不应出现在成文里")
        XCTAssertFalse(rendered.string.contains("description"), "frontmatter 字段不应出现在成文里")
        XCTAssertTrue(rendered.string.contains("正文标题"), "正文必须保留")
        XCTAssertTrue(rendered.string.contains("正文第一段"), "正文必须保留")
        XCTAssertEqual(r.frontmatterLineOffset, 4, "剥掉 4 行（开分隔 + 2 字段 + 闭分隔）")
    }

    func testNoFrontmatterUnchanged() {
        let rendered = MarkdownRenderer(theme: MarkdownTheme(), baseURL: nil)
            .render("# 没有头\n\n---\n\n正文里的分隔线还是分隔线。\n")
        XCTAssertTrue(rendered.string.contains("没有头"))
        // 正文中间的 --- 仍是水平线（被吞的是渲染成 thematicBreak，文本里本就不含 ---）
        XCTAssertFalse(rendered.string.contains("---"))
    }

    func testUnclosedFrontmatterNotStripped() {
        let rendered = MarkdownRenderer(theme: MarkdownTheme(), baseURL: nil)
            .render("---\nname: 没有闭合\n\n正文。\n")
        XCTAssertTrue(rendered.string.contains("name: 没有闭合"), "没有闭合 --- 的头不认，按正文渲染")
    }

    /// 锚点行号必须对着原始源码（编辑器行号）：frontmatter 后的第一段，
    /// 锚点行 = 原始行号（frontmatter 行数 + 正文内行号）。
    func testAnchorLinesShiftedByFrontmatter() {
        let r = MarkdownRenderer(theme: MarkdownTheme(), baseURL: nil)
        _ = r.render("---\nkey: value\n---\n第一段。\n\n第二段。\n")
        // 第一段在原始源码第 4 行，第二段第 6 行
        XCTAssertTrue(r.blockAnchors.contains { $0.sourceLine == 4 },
                      "第一段锚点应在原始第 4 行，实际：\(r.blockAnchors.prefix(5).map { $0.sourceLine })")
        XCTAssertTrue(r.blockAnchors.contains { $0.sourceLine == 6 },
                      "第二段锚点应在原始第 6 行，实际：\(r.blockAnchors.prefix(8).map { $0.sourceLine })")
    }

    /// 渐进渲染同一条剥离路径（大文档走这里）。
    func testProgressiveSessionStripsFrontmatter() throws {
        let renderer = MarkdownRenderer(theme: MarkdownTheme(), baseURL: nil)
        let session = ProgressiveRenderSession(
            renderer: renderer,
            markdown: "---\nkey: value\n---\n\n首屏段落。\n\n" + String(repeating: "后续段落。\n\n", count: 50)
        )
        let first = session.renderFirst(count: 2)
        XCTAssertFalse(first.string.contains("key:"), "渐进渲染同样不该渲染 frontmatter")
        XCTAssertEqual(renderer.frontmatterLineOffset, 3)
    }
}
