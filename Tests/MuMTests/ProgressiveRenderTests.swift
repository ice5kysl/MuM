import AppKit
import XCTest
@testable import MuM

/// 渐进渲染的验收约束第 1 条：「只改时机，不改内容」。
/// 同一篇文档，全量渲染的结果必须和渐进渲染（首屏 + 各填充片拼接）逐字、逐属性一致。
///
/// 切片预算故意用 0 / 极小 / 极大三档：预算决定切块边界，边界变了结果也必须不变。
final class ProgressiveRenderTests: XCTestCase {

    /// 覆盖所有块级结构：标题 / 段落 / 行内样式 / 嵌套列表 / 有序列表（起始编号）/
    /// 任务列表 / 嵌套引用 / 代码块 / 表格 / 分隔线 / HTML 块
    private let document = """
    # 一级标题

    正文里有 **粗体**、*斜体*、~~删除线~~、`行内代码` 和 [链接](https://example.com)。

    ## 二级标题

    - 无序甲
    - 无序乙
      - 嵌套丙

    3. 有序从三开始
    4. 有序四

    - [x] 已完成
    - [ ] 未完成

    > 引用第一段
    >
    > > 嵌套引用

    ```swift
    // 注释
    let greeting = "你好"
    ```

    | 列一 | 列二 |
    | --- | ---: |
    | 值甲 | 值乙 |
    | 值丙 | 值丁 |

    ---

    <div>html</div>

    ### 三级标题

    结尾段落。
    """

    // MARK: - 内容等价

    func testConcatEqualsFullRenderAcrossCutPointsAndBudgets() {
        let full = MarkdownRenderer(theme: MarkdownTheme(), baseURL: nil).render(document)

        for firstCount in [1, 2, 5, 80] {
            for budget in [0.0, 0.001, 60.0] {
                let joined = renderProgressively(document, firstCount: firstCount, budget: budget)
                let label = "firstCount=\(firstCount) budget=\(budget)"
                XCTAssertEqual(joined.string, full.string, "\(label)：字符串不一致")
                XCTAssertTrue(
                    strippingTables(joined).isEqual(to: strippingTables(full)),
                    "\(label)：属性不一致"
                )
                XCTAssertEqual(tableGrid(joined), tableGrid(full), "\(label)：表格结构不一致")
            }
        }
    }

    // MARK: - 大纲位置

    /// 大纲 location 必须换算成全文绝对位置 —— 片内相对位置会让跳转落错地方
    func testOutlineMatchesFullRender() {
        let fullRenderer = MarkdownRenderer(theme: MarkdownTheme(), baseURL: nil)
        _ = fullRenderer.render(document)

        for firstCount in [1, 2, 80] {
            let session = ProgressiveRenderSession(
                renderer: MarkdownRenderer(theme: MarkdownTheme(), baseURL: nil),
                markdown: document
            )
            _ = session.renderFirst(count: firstCount)
            while session.renderNext(timeBudget: 0) != nil {}
            XCTAssertTrue(session.isFinished)
            XCTAssertEqual(
                session.outline.map { "\($0.level)|\($0.location)|\($0.title)" },
                fullRenderer.outline.map { "\($0.level)|\($0.location)|\($0.title)" },
                "firstCount=\(firstCount)：大纲不一致"
            )
        }
    }

    // MARK: - 边界

    func testEdgeCases() {
        // 空文档
        assertEquivalent("", firstCount: 80)
        // 块数远少于首屏块数
        assertEquivalent("# 只有一个标题\n", firstCount: 80)
        // 单个巨型代码块（一个顶层块撑起整篇）
        let hugeCode = "```swift\n" + (0..<500).map { "let value\($0) = \($0)" }.joined(separator: "\n") + "\n```"
        assertEquivalent(hugeCode, firstCount: 80)
        // 首屏只要 1 块，其余全是填充片
        assertEquivalent(document, firstCount: 1)
    }

    // MARK: - 工具

    private func assertEquivalent(_ markdown: String, firstCount: Int) {
        let full = MarkdownRenderer(theme: MarkdownTheme(), baseURL: nil).render(markdown)
        let joined = renderProgressively(markdown, firstCount: firstCount, budget: 0)
        XCTAssertEqual(joined.string, full.string)
        XCTAssertTrue(strippingTables(joined).isEqual(to: strippingTables(full)))
        XCTAssertEqual(tableGrid(joined), tableGrid(full))
    }

    private func renderProgressively(
        _ markdown: String,
        firstCount: Int,
        budget: TimeInterval
    ) -> NSAttributedString {
        let session = ProgressiveRenderSession(
            renderer: MarkdownRenderer(theme: MarkdownTheme(), baseURL: nil),
            markdown: markdown
        )
        let joined = NSMutableAttributedString(attributedString: session.renderFirst(count: firstCount))
        while let chunk = session.renderNext(timeBudget: budget) {
            joined.append(chunk)
        }
        return joined
    }

    /// NSTextTableBlock 没有值语义相等（两次渲染各建实例），
    /// 逐属性比较前先把段落样式里的 textBlocks 摘掉；表格结构由 tableGrid 单独验。
    private func strippingTables(_ source: NSAttributedString) -> NSAttributedString {
        let copy = NSMutableAttributedString(attributedString: source)
        copy.enumerateAttribute(
            .paragraphStyle,
            in: NSRange(location: 0, length: copy.length)
        ) { value, range, _ in
            guard let style = value as? NSParagraphStyle, !style.textBlocks.isEmpty else { return }
            guard let stripped = style.mutableCopy() as? NSMutableParagraphStyle else { return }
            stripped.textBlocks = []
            copy.addAttribute(.paragraphStyle, value: stripped, range: range)
        }
        return copy
    }

    /// 表格骨架：每个含 textBlock 的段落 → 各单元的行/列/跨度的列表
    private func tableGrid(_ source: NSAttributedString) -> [[String]] {
        var grid: [[String]] = []
        source.enumerateAttribute(
            .paragraphStyle,
            in: NSRange(location: 0, length: source.length)
        ) { value, _, _ in
            guard let style = value as? NSParagraphStyle else { return }
            let cells = style.textBlocks.compactMap { $0 as? NSTextTableBlock }.map {
                "\($0.startingRow),\($0.startingColumn),\($0.rowSpan),\($0.columnSpan)"
            }
            if !cells.isEmpty { grid.append(cells) }
        }
        return grid
    }
}
