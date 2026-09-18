import XCTest
@testable import MuM

/// R-1 回归锚点（kimi `dd6e4d4`）：列表项末尾只补**无样式**范围，
/// 嵌套块（更深列表/表格/代码块）自己的段落样式不再被整铺盖掉。
/// 修复前：嵌套缩进被抹平、列表内表格塌成普通段落、代码块行距被盖。
///
/// 断言用**同一渲染器内的相对关系**（层级差、与独立块的等值），
/// 不锚定主题常量的绝对值——主题改字号行距不应弄红这些测试。
final class RendererListStructureTests: XCTestCase {

    private let renderer = MarkdownRenderer(theme: MarkdownTheme(), baseURL: nil)

    /// 取「包含 needle 的那段」首字符的段落样式
    private func style(contains needle: String, in text: NSAttributedString) -> NSParagraphStyle? {
        let range = (text.string as NSString).range(of: needle)
        guard range.location != NSNotFound else { return nil }
        return text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
    }

    func testNestedListItemKeepsDeeperIndent() {
        let out = renderer.render("- 外层\n  - 内层\n")
        let outer = style(contains: "外层", in: out)
        let inner = style(contains: "内层", in: out)
        XCTAssertNotNil(outer); XCTAssertNotNil(inner)
        XCTAssertEqual((inner?.headIndent ?? -1) - (outer?.headIndent ?? -99), 24,
                       "嵌套项比外层深 24pt（R-1 前被整铺抹成同层）")
    }

    func testSimpleListIsIndented() {
        let out = renderer.render("- 简单项\n")
        let plain = style(contains: "标题", in: renderer.render("# 标题\n")) // 基线：无缩进块
        let s = style(contains: "简单项", in: out)
        XCTAssertNotNil(plain, "标题基线应存在")
        XCTAssertNotNil(s)
        XCTAssertGreaterThan(s?.headIndent ?? -1, plain?.headIndent ?? -1,
                             "列表项有悬挂缩进（标记后内容顶住 headIndent）")
    }

    func testTableInsideListItemKeepsTextBlock() {
        let out = renderer.render("- 项\n\n  | a | b |\n  | --- | --- |\n  | 甲 | 乙 |\n")
        let range = (out.string as NSString).range(of: "甲")
        XCTAssertNotEqual(range.location, NSNotFound, "表格内容应渲染出来")
        let s = out.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
        XCTAssertTrue(s?.textBlocks.isEmpty == false, "列表内表格必须保留 NSTextTableBlock（R-1 前塌成普通行）")
    }

    func testCodeBlockInsideListItemKeepsOwnSpacing() {
        let inList = style(contains: "let x", in: renderer.render("- 项\n\n  ```swift\n  let x = 1\n  ```\n"))
        let standalone = style(contains: "let y", in: renderer.render("```swift\nlet y = 2\n```\n"))
        XCTAssertNotNil(inList); XCTAssertNotNil(standalone)
        XCTAssertEqual(inList?.lineSpacing ?? -1, standalone?.lineSpacing ?? -99,
                       "列表内代码块的行距 = 独立代码块（R-1 前被盖成全局行距）")
    }

    func testContinuationParagraphGetsListStyle() {
        let out = renderer.render("- 首段\n\n  续段\n")
        let first = style(contains: "首段", in: out)
        let cont = style(contains: "续段", in: out)
        XCTAssertNotNil(cont, "多段落项的续段应被补上列表样式（填缝），不落空")
        XCTAssertEqual(cont?.headIndent ?? -1, first?.headIndent ?? -99,
                       "续段与首段同层级缩进")
    }
}
