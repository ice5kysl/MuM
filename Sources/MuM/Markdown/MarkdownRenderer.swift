import AppKit
import Markdown

/// Markdown → NSAttributedString。
///
/// 这是「原生预览」路线的核心：swift-markdown 把文本解析成 AST（底层是 cmark-gfm，
/// 与 GitHub 同源的解析器），我们再遍历 AST 直接构造富文本。相比塞一个 WKWebView +
/// marked.js，这里没有第二个进程、没有 JS 运行时、没有 HTML 往返，预览刷新就是一次
/// 内存里的字符串构造。代价是排版效果要自己画 —— 引用竖线、分隔线、表格边框都由
/// PreviewTextView 配合自定义属性绘制。
final class MarkdownRenderer {

    private let theme: MarkdownTheme
    /// 文档所在目录，用于解析相对路径的图片
    private let baseURL: URL?

    init(theme: MarkdownTheme, baseURL: URL?) {
        self.theme = theme
        self.baseURL = baseURL
    }

    // MARK: - 入口

    /// 文档大纲的一项。`location` 是它在渲染结果里的字符位置 ——
    /// 点它就能跳到那一段，不需要把字符位置再映射回源码行。
    struct OutlineItem {
        let level: Int
        let title: String
        let location: Int
    }

    /// 最近一次 `render(_:)` 收集到的标题。渲染器是一次性的（每次重排都新建），
    /// 所以直接挂在实例上，不用回调。
    private(set) var outline: [OutlineItem] = []

    func render(_ markdown: String) -> NSAttributedString {
        let renderStart = Date()
        let document = RenderProfiler.time(.parse) { Document(parsing: markdown) }
        let output = NSMutableAttributedString()
        renderBlocks(Array(document.children), into: output, context: BlockContext())
        // 末尾多余的空行去掉，避免滚动区底部一大片空白
        trimTrailingNewlines(output)
        RenderProfiler.report(totalMS: Date().timeIntervalSince(renderStart) * 1000)
        return output
    }

    /// 【原型】渐进渲染：先渲染前 `firstBlockCount` 个顶层块并立刻回调上屏，
    /// 剩余块作为第二段返回。切分只在顶层块边界发生，BlockContext 因此总是干净的
    /// （嵌套内容都在块内部）。大纲在最后一段渲染完才完整。
    func renderProgressive(
        _ markdown: String,
        firstBlockCount: Int,
        onFirstChunk: (NSAttributedString) -> Void
    ) -> NSAttributedString {
        let document = RenderProfiler.time(.parse) { Document(parsing: markdown) }
        let all = Array(document.children)
        let cut = min(max(firstBlockCount, 0), all.count)

        let first = NSMutableAttributedString()
        renderBlocks(Array(all.prefix(cut)), into: first, context: BlockContext())
        trimTrailingNewlines(first)
        onFirstChunk(first)

        let rest = NSMutableAttributedString()
        renderBlocks(Array(all.dropFirst(cut)), into: rest, context: BlockContext())
        trimTrailingNewlines(rest)
        return rest
    }

    /// 纯文本渲染（无扩展名的文本文件走这里）
    func renderPlainText(_ text: String) -> NSAttributedString {
        let style = paragraphStyle(indent: 0, spacingBefore: 0, spacingAfter: 0)
        let result = NSMutableAttributedString(string: text, attributes: [
            .font: theme.codeBlockFont,
            .foregroundColor: theme.textColor,
            .paragraphStyle: style,
        ])
        return result
    }

    /// 代码文件预览：整篇按语言做语法高亮
    func renderCode(_ text: String, language: String?) -> NSAttributedString {
        let style = paragraphStyle(indent: 0, spacingBefore: 0, spacingAfter: 0, lineSpacing: 2)
        let highlighted = RenderProfiler.time(.highlight) {
            NSMutableAttributedString(
                attributedString: CodeHighlighter.highlight(text, language: language, theme: theme)
            )
        }
        highlighted.addAttribute(
            .paragraphStyle,
            value: style,
            range: NSRange(location: 0, length: highlighted.length)
        )
        return highlighted
    }


    // MARK: - 块级上下文

    private struct BlockContext {
        var indent: CGFloat = 0
        var listDepth = 0
        var quoteDepth = 0

        func nestedList() -> BlockContext {
            var copy = self
            copy.listDepth += 1
            copy.indent += 24
            return copy
        }

        func nestedQuote() -> BlockContext {
            var copy = self
            copy.quoteDepth += 1
            copy.indent += 18
            return copy
        }
    }

    // MARK: - 段落样式

    private func paragraphStyle(
        indent: CGFloat,
        firstLineIndent: CGFloat? = nil,
        spacingBefore: CGFloat = 0,
        spacingAfter: CGFloat = 0,
        lineSpacing: CGFloat? = nil,
        markerWidth: CGFloat? = nil
    ) -> NSMutableParagraphStyle {
        let style = NSMutableParagraphStyle()
        // 行距和段间距都跟着设置面板走；传 nil 表示用全局行距，
        // 代码块这种需要更紧的块会显式传一个小值。
        style.lineSpacing = lineSpacing ?? theme.lineSpacing
        style.paragraphSpacingBefore = spacingBefore * theme.blockSpacingScale
        style.paragraphSpacing = spacingAfter * theme.blockSpacingScale
        style.firstLineHeadIndent = firstLineIndent ?? indent
        style.headIndent = indent
        if let markerWidth {
            style.tabStops = [NSTextTab(textAlignment: .left, location: indent + markerWidth)]
        }
        return style
    }

    // MARK: - 块级渲染

    private func renderBlocks(_ blocks: [Markup], into out: NSMutableAttributedString, context: BlockContext) {
        for block in blocks {
            renderBlock(block, into: out, context: context)
        }
    }

    private func renderBlock(_ block: Markup, into out: NSMutableAttributedString, context: BlockContext) {
        switch block {

        case let heading as Heading:
            renderHeading(heading, into: out, context: context)

        case let paragraph as Paragraph:
            renderParagraph(paragraph, into: out, context: context)

        case let codeBlock as CodeBlock:
            renderCodeBlock(codeBlock, into: out, context: context)

        case let quote as BlockQuote:
            renderBlockQuote(quote, into: out, context: context)

        case let list as UnorderedList:
            renderList(list, isOrdered: false, into: out, context: context)

        case let list as OrderedList:
            renderList(list, isOrdered: true, into: out, context: context)

        case let table as Table:
            RenderProfiler.time(.tables) {
                renderTable(table, into: out, context: context)
            }

        case is ThematicBreak:
            renderThematicBreak(into: out, context: context)

        case let html as HTMLBlock:
            let style = paragraphStyle(indent: context.indent, spacingBefore: 10, spacingAfter: 10)
            let text = NSMutableAttributedString(string: html.rawHTML + "\n", attributes: [
                .font: theme.codeBlockFont,
                .foregroundColor: theme.tertiaryTextColor,
                .paragraphStyle: style,
            ])
            out.append(text)

        default:
            // 未知块级节点：递归它的子节点，尽量不丢内容
            let children = Array(block.children)
            if children.isEmpty {
                let text = plainText(of: block)
                if !text.isEmpty {
                    renderParagraphText(text, into: out, context: context)
                }
            } else {
                renderBlocks(children, into: out, context: context)
            }
        }

    }

    private func renderHeading(_ heading: Heading, into out: NSMutableAttributedString, context: BlockContext) {
        // 记下它在渲染结果中的位置，供大纲跳转用。
        // 只收层级 1…3 —— 更深的标题进大纲只会让列表变长，不会让它更有用。
        if heading.level <= 3, context.indent == 0 {
            let title = plainText(of: heading).trimmingCharacters(in: .whitespacesAndNewlines)
            if !title.isEmpty {
                outline.append(OutlineItem(level: heading.level, title: title, location: out.length))
            }
        }

        let level = min(max(heading.level, 1), 6)
        let fonts = theme.headingFonts
        let font = fonts.indices.contains(level - 1) ? fonts[level - 1] : fonts[0]

        let spacingBefore: CGFloat = level == 1 ? 26 : (level == 2 ? 20 : 15)
        let style = paragraphStyle(
            indent: context.indent,
            spacingBefore: spacingBefore,
            spacingAfter: level <= 2 ? 12 : 8
        )

        let text = NSMutableAttributedString()
        RenderProfiler.time(.inlines) {
            renderInlines(Array(heading.children), into: text, style: InlineStyle(), context: context)
        }
        // 换行符也要在同一段样式范围内：TextKit 按段落终止符所在位置的属性
        // 决定整段的段落样式，漏掉它会让标题的间距时而生效时而不生效。
        text.append(NSAttributedString(string: "\n"))

        let range = NSRange(location: 0, length: text.length)
        text.addAttributes([
            .font: font,
            .foregroundColor: theme.headingColor,
            .paragraphStyle: style,
        ], range: range)

        if level <= 2 {
            text.addAttribute(.mumHeadingRule, value: level, range: range)
        }

        applyQuoteMarkers(to: text, context: context)
        out.append(text)
    }

    private func renderParagraph(_ paragraph: Paragraph, into out: NSMutableAttributedString, context: BlockContext) {
        let style = paragraphStyle(
            indent: context.indent,
            spacingBefore: context.quoteDepth > 0 ? 4 : 0,
            spacingAfter: 8
        )

        let text = NSMutableAttributedString()
        RenderProfiler.time(.inlines) {
            renderInlines(Array(paragraph.children), into: text, style: InlineStyle(), context: context)
        }
        text.append(NSAttributedString(string: "\n"))
        text.addAttribute(.paragraphStyle, value: style, range: NSRange(location: 0, length: text.length))
        applyQuoteMarkers(to: text, context: context)
        out.append(text)
    }

    private func renderParagraphText(_ raw: String, into out: NSMutableAttributedString, context: BlockContext) {
        let style = paragraphStyle(indent: context.indent, spacingAfter: 12)
        let text = NSMutableAttributedString(string: raw, attributes: [
            .font: theme.bodyFont,
            .foregroundColor: theme.textColor,
            .paragraphStyle: style,
        ])
        text.append(NSAttributedString(string: "\n"))
        out.append(text)
    }

    private func renderCodeBlock(_ codeBlock: CodeBlock, into out: NSMutableAttributedString, context: BlockContext) {
        var code = codeBlock.code
        if !code.hasSuffix("\n") { code += "\n" }

        let highlighted = RenderProfiler.time(.highlight) {
            NSMutableAttributedString(
                attributedString: CodeHighlighter.highlight(code, language: codeBlock.language, theme: theme)
            )
        }

        // 底色不交给 TextKit 的 `.backgroundColor`：它填首行时从 firstLineHeadIndent 起算，
        // 填续行时却从行片段原点起算（忽略 headIndent），于是代码块左上角会缺一角。
        // 改由 PreviewLayoutManager 在文字**之下**统一绘制整块底色，见那里的说明。
        let style = paragraphStyle(
            indent: context.indent + 12,
            spacingBefore: 10,
            spacingAfter: 0,
            lineSpacing: 4
        )
        style.firstLineHeadIndent = context.indent + 12
        style.tailIndent = -(context.indent + 12)

        let full = NSRange(location: 0, length: highlighted.length)
        highlighted.addAttributes([
            .paragraphStyle: style,
            .mumCodeBlock: theme.codeBlockBackground,
        ], range: full)
        applyQuoteMarkers(to: highlighted, context: context)

        out.append(highlighted)

        // 代码块之后垫一个空行，做出和正文的间隔
        out.append(NSAttributedString(string: "\n", attributes: [
            .paragraphStyle: NSMutableParagraphStyle(),
            .font: theme.codeBlockFont,
        ]))
    }

    private func renderBlockQuote(_ quote: BlockQuote, into out: NSMutableAttributedString, context: BlockContext) {
        let nested = context.nestedQuote()
        let start = out.length
        renderBlocks(Array(quote.children), into: out, context: nested)

        let range = NSRange(location: start, length: out.length - start)
        guard range.length > 0 else { return }

        // 内层引用渲染时已经写入了更深的 depth。这里只补还没有标记的部分，
        // 否则外层会把内层的深度整个覆盖回去，嵌套引用就退化成一层。
        var unmarked: [NSRange] = []
        out.enumerateAttribute(.mumQuoteDepth, in: range, options: []) { value, subrange, _ in
            if value == nil { unmarked.append(subrange) }
        }
        for subrange in unmarked {
            out.addAttribute(.mumQuoteDepth, value: nested.quoteDepth, range: subrange)
        }

        out.addAttribute(.mumQuoteColor, value: theme.quoteBarColor, range: range)
    }

    private func renderList(_ list: Markup, isOrdered: Bool, into out: NSMutableAttributedString, context: BlockContext) {
        let nested = context.nestedList()
        let items = Array(list.children)

        var ordinal = 1
        if isOrdered, let ordered = list as? OrderedList {
            ordinal = Int(ordered.startIndex)
        }

        for item in items {
            let marker: String
            if let listItem = item as? ListItem, let checkbox = listItem.checkbox {
                marker = checkbox == .checked ? "☑" : "☐"
            } else if isOrdered {
                marker = "\(ordinal)."
                ordinal += 1
            } else {
                marker = bullet(for: nested.listDepth)
            }

            renderListItem(item, marker: marker, into: out, context: nested)
        }
    }

    private func bullet(for depth: Int) -> String {
        switch (depth - 1) % 3 {
        case 0: return "•"
        case 1: return "◦"
        default: return "▪"
        }
    }

    private func renderListItem(_ item: Markup, marker: String, into out: NSMutableAttributedString, context: BlockContext) {
        let content = NSMutableAttributedString()
        renderBlocks(Array(item.children), into: content, context: context)

        let markerWidth: CGFloat = marker.count > 2 ? 30 : 22
        let style = paragraphStyle(
            indent: context.indent,
            firstLineIndent: context.indent,
            spacingAfter: 5,
            markerWidth: markerWidth
        )

        // 标记 + 制表符：换行后由 headIndent 顶住，形成悬挂缩进
        let markerText = NSMutableAttributedString(string: marker + "\t", attributes: [
            .font: theme.bodyFont,
            .foregroundColor: theme.secondaryTextColor,
            .paragraphStyle: style,
        ])

        let start = out.length
        out.append(markerText)
        out.append(content)

        // 整项（含标记）统一段落样式；首行的 firstLineHeadIndent 让标记贴左
        let range = NSRange(location: start, length: out.length - start)
        out.addAttribute(.paragraphStyle, value: style, range: range)
    }

    private func renderThematicBreak(into out: NSMutableAttributedString, context: BlockContext) {
        let style = paragraphStyle(indent: 0, spacingBefore: 18, spacingAfter: 18)
        let text = NSMutableAttributedString(string: "\u{00A0}\n", attributes: [
            .font: theme.bodyFont,
            .paragraphStyle: style,
            .mumHorizontalRule: true,
        ])
        out.append(text)
    }

    // MARK: - 表格

    private func renderTable(_ table: Table, into out: NSMutableAttributedString, context: BlockContext) {
        let headCells = Array(table.head.cells)
        let bodyRows = Array(table.body.rows)
        let widestBodyRow = bodyRows.map { Array($0.cells).count }.max() ?? 0
        let columnCount = max(headCells.count, widestBodyRow, 1)

        let textTable = NSTextTable()
        textTable.numberOfColumns = columnCount
        textTable.collapsesBorders = true
        textTable.hidesEmptyCells = false

        let alignments = table.columnAlignments

        func appendRow(_ cells: [Markdown.Table.Cell], rowIndex: Int, isHeader: Bool) {
            for (columnIndex, cell) in cells.enumerated() where columnIndex < columnCount {
                // colspan 为 0 表示这一格被左边的单元格跨过去了
                guard cell.colspan > 0 else { continue }

                let block = NSTextTableBlock(
                    table: textTable,
                    startingRow: rowIndex,
                    rowSpan: max(Int(cell.rowspan), 1),
                    startingColumn: columnIndex,
                    columnSpan: max(Int(cell.colspan), 1)
                )
                block.backgroundColor = isHeader ? theme.tableHeaderBackground : nil
                block.setBorderColor(theme.tableBorderColor)
                block.setWidth(1, type: .absoluteValueType, for: .border)
                block.setWidth(7, type: .absoluteValueType, for: .padding)

                let style = NSMutableParagraphStyle()
                style.textBlocks = [block]
                style.lineSpacing = 2

                if columnIndex < alignments.count, let alignment = alignments[columnIndex] {
                    switch alignment {
                    case .left: style.alignment = .left
                    case .center: style.alignment = .center
                    case .right: style.alignment = .right
                    }
                }

                let cellText = NSMutableAttributedString()
                RenderProfiler.time(.inlines) {
                    renderInlines(Array(cell.children), into: cellText, style: InlineStyle(), context: context)
                }
                if cellText.length == 0 {
                    cellText.append(NSAttributedString(string: " "))
                }
                cellText.append(NSAttributedString(string: "\n"))
                cellText.addAttributes([
                    .paragraphStyle: style,
                    .font: isHeader ? theme.boldFont : theme.bodyFont,
                    .foregroundColor: theme.textColor,
                ], range: NSRange(location: 0, length: cellText.length))

                out.append(cellText)
            }
        }

        appendRow(headCells, rowIndex: 0, isHeader: true)
        for (offset, row) in bodyRows.enumerated() {
            appendRow(Array(row.cells), rowIndex: offset + 1, isHeader: false)
        }

        // 表格与后文之间留白
        let spacer = paragraphStyle(indent: 0, spacingAfter: 10)
        out.append(NSAttributedString(string: "\n", attributes: [.paragraphStyle: spacer, .font: theme.bodyFont]))
    }

    // MARK: - 行内渲染

    private struct InlineStyle {
        var bold = false
        var italic = false
        var strikethrough = false
        var code = false
        var link: URL?
    }

    private func renderInlines(_ nodes: [Markup], into out: NSMutableAttributedString, style: InlineStyle, context: BlockContext) {
        for node in nodes {
            renderInline(node, into: out, style: style, context: context)
        }
    }

    private func renderInline(_ node: Markup, into out: NSMutableAttributedString, style: InlineStyle, context: BlockContext) {
        switch node {

        case let text as Text:
            out.append(NSAttributedString(string: text.string, attributes: attributes(for: style)))

        case let emphasis as Emphasis:
            var next = style; next.italic = true
            renderInlines(Array(emphasis.children), into: out, style: next, context: context)

        case let strong as Strong:
            var next = style; next.bold = true
            renderInlines(Array(strong.children), into: out, style: next, context: context)

        case let strike as Strikethrough:
            var next = style; next.strikethrough = true
            renderInlines(Array(strike.children), into: out, style: next, context: context)

        case let code as InlineCode:
            var next = style; next.code = true
            out.append(NSAttributedString(string: code.code, attributes: attributes(for: next)))

        case let link as Link:
            var next = style
            if let destination = link.destination {
                next.link = resolvedURL(destination)
            }
            renderInlines(Array(link.children), into: out, style: next, context: context)

        case let image as Image:
            appendImage(image, into: out, style: style)

        case is SoftBreak:
            out.append(NSAttributedString(string: " ", attributes: attributes(for: style)))

        case is LineBreak:
            out.append(NSAttributedString(string: "\n", attributes: attributes(for: style)))

        case let html as InlineHTML:
            out.append(NSAttributedString(string: html.rawHTML, attributes: [
                .font: theme.codeFont,
                .foregroundColor: theme.tertiaryTextColor,
            ]))

        default:
            let children = Array(node.children)
            if children.isEmpty {
                let plain = plainText(of: node)
                if !plain.isEmpty {
                    out.append(NSAttributedString(string: plain, attributes: attributes(for: style)))
                }
            } else {
                renderInlines(children, into: out, style: style, context: context)
            }
        }
    }

    /// `plainText` 声明在 `PlainTextConvertibleMarkup` 上而不是 `Markup` 上，
    /// 走协议查询而不是直接取属性。
    private func plainText(of markup: Markup) -> String {
        (markup as? PlainTextConvertibleMarkup)?.plainText ?? ""
    }

    private func attributes(for style: InlineStyle) -> [NSAttributedString.Key: Any] {
        var attributes: [NSAttributedString.Key: Any] = [.font: font(for: style)]

        // 字间距。行内代码不参与 —— 等宽字体再拉开间距会散架。
        if theme.letterSpacing != 0, !style.code {
            attributes[.kern] = theme.letterSpacing
        }

        if style.code {
            attributes[.foregroundColor] = theme.codeTextColor
            attributes[.backgroundColor] = theme.inlineCodeBackground
        } else if let link = style.link {
            attributes[.foregroundColor] = theme.linkColor
            attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            attributes[.link] = link
        } else {
            attributes[.foregroundColor] = theme.textColor
        }

        if style.strikethrough {
            attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
        }
        return attributes
    }

    private func font(for style: InlineStyle) -> NSFont {
        if style.code {
            return style.bold ? theme.codeBoldFont : theme.codeFont
        }
        switch (style.bold, style.italic) {
        case (true, true): return theme.boldItalicFont
        case (true, false): return theme.boldFont
        case (false, true): return theme.italicFont
        case (false, false): return theme.bodyFont
        }
    }

    // MARK: - 图片

    private static let imageCache = ConcurrentCache<NSImage>()
    private static let maxImageWidth: CGFloat = 680

    private func appendImage(_ image: Image, into out: NSMutableAttributedString, style: InlineStyle) {
        let alt = plainText(of: image)
        guard let destination = image.source,
              let url = resolvedURL(destination),
              url.isFileURL else {
            appendImagePlaceholder(alt.isEmpty ? "图片" : alt, into: out)
            return
        }

        let key = url.path
        let loaded: NSImage?
        if let cached = Self.imageCache[key] {
            loaded = cached
        } else {
            loaded = RenderProfiler.time(.images) { NSImage(contentsOf: url) }
            if let loaded { Self.imageCache[key] = loaded }
        }
        guard let source = loaded else {
            appendImagePlaceholder("找不到图片：\(alt.isEmpty ? url.lastPathComponent : alt)", into: out)
            return
        }

        let size = scaledSize(for: source)
        let attachment = NSTextAttachment()
        attachment.image = source
        attachment.bounds = CGRect(origin: .zero, size: size)

        out.append(NSAttributedString(attachment: attachment))
        if !alt.isEmpty {
            out.append(NSAttributedString(string: "\n" + alt, attributes: [
                .font: NSFont.systemFont(ofSize: max(theme.baseSize - 3, 9)),
                .foregroundColor: theme.tertiaryTextColor,
            ]))
        }
    }

    private func scaledSize(for image: NSImage) -> NSSize {
        let size = image.size
        guard size.width > Self.maxImageWidth, size.width > 0 else { return size }
        let ratio = Self.maxImageWidth / size.width
        return NSSize(width: Self.maxImageWidth, height: (size.height * ratio).rounded())
    }

    private func appendImagePlaceholder(_ label: String, into out: NSMutableAttributedString) {
        out.append(NSAttributedString(string: "🖼 \(label)", attributes: [
            .font: NSFont.systemFont(ofSize: max(theme.baseSize - 2, 10)),
            .foregroundColor: theme.tertiaryTextColor,
        ]))
    }

    // MARK: - 工具

    private func resolvedURL(_ destination: String) -> URL? {
        if let url = URL(string: destination), url.scheme != nil {
            return url
        }
        guard let baseURL else { return URL(string: destination) }
        let decoded = destination.removingPercentEncoding ?? destination
        return URL(fileURLWithPath: decoded, relativeTo: baseURL).standardizedFileURL
    }

    private func applyQuoteMarkers(to text: NSMutableAttributedString, context: BlockContext) {
        guard context.quoteDepth > 0, text.length > 0 else { return }
        let range = NSRange(location: 0, length: text.length)
        text.addAttribute(.mumQuoteDepth, value: context.quoteDepth, range: range)
        text.addAttribute(.mumQuoteColor, value: theme.quoteBarColor, range: range)
        // 引用内文字降一档对比度
        text.enumerateAttribute(.foregroundColor, in: range, options: []) { value, subrange, _ in
            guard let color = value as? NSColor, color == self.theme.textColor else { return }
            text.addAttribute(.foregroundColor, value: self.theme.quoteTextColor, range: subrange)
        }
    }

    private func trimTrailingNewlines(_ text: NSMutableAttributedString) {
        while text.length > 0 {
            let last = text.string.utf16[text.string.utf16.index(text.string.utf16.startIndex, offsetBy: text.length - 1)]
            guard last == 0x0A else { break }
            text.deleteCharacters(in: NSRange(location: text.length - 1, length: 1))
        }
    }
}
