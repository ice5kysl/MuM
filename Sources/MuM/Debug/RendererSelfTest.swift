import AppKit

/// 无界面自检：不启动窗口，直接把 Markdown 渲染成富文本，再检查结果的属性结构。
///
/// 为什么值得存在：预览区是 MuM 唯一的「输出」，而它的正确性完全体现在
/// NSAttributedString 的属性上（段落样式、文本表格、自定义装饰标记）。这些用肉眼
/// 看截图只能看个大概，用断言查属性才是确定的。跑 `MuM --selftest` 即可。
enum RendererSelfTest {

    /// 返回进程退出码
    static func run(arguments: [String]) -> Int32 {
        if arguments.contains("--dump-lines") {
            return dumpLines()
        }
        // 带文件路径时只做一次「结构报告」，方便人工核对渲染结果
        if let path = arguments.first(where: { !$0.hasPrefix("-") && $0 != arguments[0] }) {
            return report(path: path)
        }
        return assertFixture() ? 0 : 1
    }

    // MARK: - 行几何诊断

    /// 打印每一行的行片段矩形与已用矩形。
    ///
    /// 用来查"背景色缺一角"这类问题：`.backgroundColor` 是按行片段填的，
    /// 一旦首行的片段矩形和其余行不一致，就会露出白边。
    private static func dumpLines() -> Int32 {
        let markdown = """
        ## 构建

        ```bash
        # iOS（模拟器）
        xcodebuild -project A.xcodeproj -scheme A \\
        ```
        """

        let renderer = MarkdownRenderer(theme: MarkdownTheme(), baseURL: nil)
        let rendered = renderer.render(markdown)
        let text = rendered.string as NSString

        let storage = NSTextStorage(attributedString: rendered)
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 700, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)
        layout.ensureLayout(for: container)

        print("行几何（容器宽 700，lineFragmentPadding 0）")
        print(String(repeating: "─", count: 84))
        print(String(format: "%-34s %-26s %-26s", "行内容", "行片段矩形 x/w", "已用矩形 x/w"))

        var glyphIndex = 0
        while glyphIndex < layout.numberOfGlyphs {
            var glyphRange = NSRange()
            let fragment = layout.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &glyphRange)
            let used = layout.lineFragmentUsedRect(forGlyphAt: glyphIndex, effectiveRange: nil)
            let charRange = layout.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

            var raw = charRange.length > 0 ? text.substring(with: charRange) : ""
            raw = raw.replacingOccurrences(of: "\n", with: "⏎")
            if raw.count > 30 { raw = String(raw.prefix(30)) + "…" }

            let fragmentText = String(format: "x=%.1f w=%.1f", fragment.minX, fragment.width)
            let usedText = String(format: "x=%.1f w=%.1f", used.minX, used.width)
            print(String(format: "%-34@ %-26@ %-26@", raw as NSString, fragmentText as NSString, usedText as NSString))

            glyphIndex = NSMaxRange(glyphRange)
        }
        return 0
    }

    // MARK: - 结构报告

    private static func report(path: String) -> Int32 {
        let url = URL(fileURLWithPath: path)
        guard let source = try? String(contentsOf: url, encoding: .utf8) else {
            print("无法读取：\(path)")
            return 1
        }

        let theme = MarkdownTheme()
        let renderer = MarkdownRenderer(theme: theme, baseURL: url.deletingLastPathComponent())
        let output = renderer.render(source)

        print("文件：\(url.lastPathComponent)  字符数：\(output.length)")
        print(String(repeating: "─", count: 72))

        for (text, attributes) in paragraphs(of: output) {
            print(describe(text: text, attributes: attributes))
        }
        return 0
    }

    // MARK: - 断言

    private static let fixture = """
    # 一级标题

    正文里有 **粗体**、*斜体*、~~删除线~~、`行内代码` 和 [链接](https://example.com)。

    ## 二级标题

    ### 三级标题

    - 无序甲
    - 无序乙
      - 嵌套丙

    1. 有序一
    2. 有序二

    - [x] 已完成
    - [ ] 未完成

    > 引用第一段
    >
    > > 嵌套引用

    ```swift
    // 注释
    let greeting = "你好"
    if greeting.isEmpty { return }
    ```

    | 列一 | 列二 |
    | --- | ---: |
    | 值甲 | 值乙 |

    ---

    ![替代文字](missing.png)
    """

    private static func assertFixture() -> Bool {
        let theme = MarkdownTheme()
        let renderer = MarkdownRenderer(theme: theme, baseURL: nil)
        let output = renderer.render(fixture)
        let items = paragraphs(of: output)

        var passed = 0
        var failed = 0

        func check(_ label: String, _ condition: Bool, detail: String = "") {
            if condition {
                passed += 1
                print("  ✓ \(label)")
            } else {
                failed += 1
                print("  ✗ \(label)\(detail.isEmpty ? "" : "  — \(detail)")")
            }
        }

        func find(_ needle: String) -> (String, [NSAttributedString.Key: Any])? {
            items.first { $0.0.contains(needle) }
        }

        print("MuM 渲染自检（\(items.count) 个段落）")
        print(String(repeating: "─", count: 72))

        check("输出非空", output.length > 0)

        // 标题：一级/二级带下划线标记，三级不带
        if let (text, attributes) = find("一级标题") {
            check("h1 有下划线标记", attributes[.mumHeadingRule] != nil, detail: text)
            let font = attributes[.font] as? NSFont
            check("h1 字号大于正文", (font?.pointSize ?? 0) > theme.baseSize)
        } else {
            check("找到 h1", false)
        }

        if let (_, attributes) = find("二级标题") {
            check("h2 有下划线标记", attributes[.mumHeadingRule] != nil)
        } else {
            check("找到 h2", false)
        }

        if let (_, attributes) = find("三级标题") {
            check("h3 无下划线标记", attributes[.mumHeadingRule] == nil)
        } else {
            check("找到 h3", false)
        }

        // 行内样式
        let inlineRun = inlineAttributes(in: output)
        check("粗体字号/字重存在", inlineRun.contains { ($0[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.bold) == true })
        check("斜体存在", inlineRun.contains { ($0[.font] as? NSFont)?.fontDescriptor.symbolicTraits.contains(.italic) == true })
        check("删除线存在", inlineRun.contains { $0[.strikethroughStyle] != nil })
        check("行内代码有底色", inlineRun.contains { $0[.backgroundColor] != nil })
        check("链接有 .link 属性", inlineRun.contains { $0[.link] != nil })

        // 列表
        check("无序列表用 • 标记", find("无序甲")?.0.hasPrefix("•") == true)
        check("嵌套无序列表用 ◦ 标记", find("嵌套丙")?.0.hasPrefix("◦") == true, detail: find("嵌套丙")?.0 ?? "")
        check("有序列表从 1. 开始", find("有序一")?.0.hasPrefix("1.") == true, detail: find("有序一")?.0 ?? "")
        check("有序列表递增到 2.", find("有序二")?.0.hasPrefix("2.") == true, detail: find("有序二")?.0 ?? "")

        // 任务列表
        check("任务列表已勾选为 ☑", find("已完成")?.0.contains("☑") == true, detail: find("已完成")?.0 ?? "")
        check("任务列表未勾选为 ☐", find("未完成")?.0.contains("☐") == true, detail: find("未完成")?.0 ?? "")

        // 引用
        check("引用深度为 1", find("引用第一段")?.1[.mumQuoteDepth] as? Int == 1)
        check("嵌套引用深度为 2", find("嵌套引用")?.1[.mumQuoteDepth] as? Int == 2,
              detail: String(describing: find("嵌套引用")?.1[.mumQuoteDepth]))

        // 代码块：等宽字体 + 底色 + 语法高亮（至少两种前景色）
        if let (_, attributes) = find("greeting") {
            check("代码块带底色标记", attributes[.mumCodeBlock] != nil)
            let fonts = codeRunFonts(in: output)
            check("代码块用等宽字体", fonts.contains { $0.isFixedPitch })
        } else {
            check("找到代码块", false)
        }
        let codeColors = codeForegroundColors(in: output)
        check("代码块有语法高亮（≥2 种颜色）", codeColors.count >= 2, detail: "\(codeColors.count) 种")

        // 表格
        check("表格生成了 NSTextTableBlock", output.textTableBlocks() > 0,
              detail: "\(output.textTableBlocks()) 个")

        // 分隔线
        check("分隔线有标记", items.contains { $0.1[.mumHorizontalRule] != nil })

        // 图片占位（源文件不存在时降级为占位符而不是崩溃）
        check("缺失图片降级为占位符", output.string.contains("🖼"))

        print(String(repeating: "─", count: 72))
        print("通过 \(passed)，失败 \(failed)")
        return failed == 0
    }

    // MARK: - 解析辅助

    /// 按段落切分，返回（段落文本, 段首属性）
    private static func paragraphs(of text: NSAttributedString) -> [(String, [NSAttributedString.Key: Any])] {
        var result: [(String, [NSAttributedString.Key: Any])] = []
        let string = text.string as NSString
        var location = 0

        while location < string.length {
            let lineRange = string.lineRange(for: NSRange(location: location, length: 0))
            var content = string.substring(with: lineRange)
            if content.hasSuffix("\n") { content.removeLast() }
            let attributes = text.attributes(at: location, effectiveRange: nil)
            result.append((content, attributes))
            location = lineRange.location + lineRange.length
        }
        return result
    }

    /// 所有非空 run 的属性
    private static func inlineAttributes(in text: NSAttributedString) -> [[NSAttributedString.Key: Any]] {
        var result: [[NSAttributedString.Key: Any]] = []
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length), options: []) { attributes, range, _ in
            guard text.string.utf16.count >= range.location + range.length else { return }
            let snippet = (text.string as NSString).substring(with: range)
            guard !snippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            result.append(attributes)
        }
        return result
    }

    private static func codeRunFonts(in text: NSAttributedString) -> [NSFont] {
        var fonts: [NSFont] = []
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length), options: []) { value, _, _ in
            if let font = value as? NSFont, font.isFixedPitch { fonts.append(font) }
        }
        return fonts
    }

    private static func codeForegroundColors(in text: NSAttributedString) -> Set<String> {
        var colors: Set<String> = []
        // 代码块底色改用自定义属性 .mumCodeBlock 标记（由 PreviewLayoutManager 绘制），
        // 所以按它来圈定范围。
        text.enumerateAttribute(.mumCodeBlock, in: NSRange(location: 0, length: text.length), options: []) { value, range, _ in
            guard value != nil else { return }
            text.enumerateAttribute(.foregroundColor, in: range, options: []) { color, _, _ in
                if let color = color as? NSColor { colors.insert(color.description) }
            }
        }
        return colors
    }

    private static func describe(text: String, attributes: [NSAttributedString.Key: Any]) -> String {
        var tags: [String] = []

        if let rule = attributes[.mumHeadingRule] { tags.append("heading-rule:\(rule)") }
        if let depth = attributes[.mumQuoteDepth] { tags.append("quote:\(depth)") }
        if attributes[.mumHorizontalRule] != nil { tags.append("hr") }
        if let font = attributes[.font] as? NSFont { tags.append("font:\(Int(font.pointSize))") }
        if let blocks = (attributes[.paragraphStyle] as? NSParagraphStyle)?.textBlocks, !blocks.isEmpty {
            tags.append("table-block:\(blocks.count)")
        }

        let preview = text.count > 56 ? String(text.prefix(56)) + "…" : text
        return "[\(tags.joined(separator: " "))] \(preview)"
    }
}

private extension NSAttributedString {
    /// 统计带文本表格块的段落数，用于验证 GFM 表格确实走了 NSTextTable
    func textTableBlocks() -> Int {
        var count = 0
        enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: length), options: []) { value, _, _ in
            guard let style = value as? NSParagraphStyle, !style.textBlocks.isEmpty else { return }
            count += 1
        }
        return count
    }
}
