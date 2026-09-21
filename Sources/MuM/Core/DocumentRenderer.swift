import AppKit
import PDFKit
import UniformTypeIdentifiers

/// 文档正文的离屏渲染：markdown → PNG 长图 / 分页 PDF。
///
/// 应用内导出（⌘⇧E）和 headless CLI（`MuM render`）共用这一个入口 ——
/// 两条路出同样的图，才敢说"agent 看到的就是用户看到的"。
///
/// 只出正文：不含窗口 chrome、侧栏、状态栏。排版体系与预览一致
/// （PreviewLayoutManager + PreviewTextView 的装饰绘制），渲染器就是产线的
/// `MarkdownRenderer` —— 不是另起炉灶的"导出样式"。
enum DocumentRenderer {

    /// 导出格式。··· 菜单按它预选格式，保存面板不再让用户选。
    enum Format {
        case png
        case pdf

        var contentType: UTType { self == .png ? .png : .pdf }
        var pathExtension: String { self == .png ? "png" : "pdf" }
    }

    enum ExportError: LocalizedError {
        /// 输出扩展名不是 png / pdf
        case unsupportedFormat(String)
        /// 排版或位图/PDF 编码失败
        case encodeFailed
        /// 图片 / PDF 这类非文本内容没有"导出渲染结果"这回事
        case notTextual

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat(let ext): return "不支持的导出格式：.\(ext)（只支持 png / pdf）"
            case .encodeFailed: return "渲染结果编码失败"
            case .notTextual: return "只有文本类文档可以导出渲染结果"
            }
        }
    }

    /// 渲染参数。默认值对齐 `MuMSettings()` 的出厂值；
    /// 应用内导出时由窗口控制器用当前设置逐项覆盖。
    struct Options {
        /// 正文宽度（pt），默认 780 = 设置里的"标准"阅读宽度
        var width: CGFloat = CGFloat(MuMSettings().readingWidth.rawValue)
        /// 阅读主题（纸色）
        var readingTheme: ReadingTheme = MuMSettings().readingTheme
        var fontSize: CGFloat = MuMSettings().previewFontSize
        var lineSpacing: CGFloat = MuMSettings().lineSpacing
        var blockSpacing: CGFloat = MuMSettings().blockSpacing
        var letterSpacing: CGFloat = MuMSettings().letterSpacing
        var previewFont: PreviewFont = MuMSettings().previewFont
        /// true/false 钉住明暗；nil = 跟随当前 app 外观（应用内导出的语义）
        var dark: Bool? = nil
    }

    /// 排版结果：渲染好的富文本 + 大纲 + 耗时。`check` / `outline` 命令也用它。
    struct Rendered {
        let attributed: NSAttributedString
        let outline: [MarkdownRenderer.OutlineItem]
        let renderMS: Double
        /// 阅读面底色（来自主题色板；system 主题下是动态色，绘制时按外观解析）
        let backgroundColor: NSColor
        /// 分页指令（<div style="page-break-after: always"> 等）在成文中的字符位置，
        /// PDF 导出在这些位置强制换页；PNG 长图没有页的概念，忽略
        var pageBreaks: [Int] = []
    }

    // MARK: - 排版（与预览同一入口）

    /// 用产线渲染器把文本排版成富文本。kind 语义与打开文件时一致：
    /// markdown 走完整渲染，代码走语法高亮，纯文本走等宽排版。
    static func render(
        text: String,
        kind: FileKind = .markdown,
        baseURL: URL?,
        options: Options
    ) -> Rendered {
        var theme = MarkdownTheme()
        theme.baseSize = options.fontSize
        theme.lineSpacing = options.lineSpacing
        theme.blockSpacingScale = options.blockSpacing
        theme.letterSpacing = options.letterSpacing
        theme.previewFont = options.previewFont
        theme.readingTheme = options.readingTheme
        theme.maxContentWidth = options.width

        let renderer = MarkdownRenderer(theme: theme, baseURL: baseURL)
        let start = Date()
        let attributed: NSAttributedString
        switch kind {
        case .markdown:
            attributed = renderer.render(text)
        case .code:
            attributed = renderer.renderCode(text, language: nil)
        default:
            attributed = renderer.renderPlainText(text)
        }
        return Rendered(
            attributed: attributed,
            outline: renderer.outline,
            renderMS: Date().timeIntervalSince(start) * 1000,
            backgroundColor: theme.backgroundColor,
            pageBreaks: renderer.pageBreakLocations
        )
    }

    // MARK: - 出图

    /// PNG 长图：多长的文档都是一张图。
    static func png(_ rendered: Rendered, options: Options) -> Data? {
        let view = makeTextView(rendered, options: options)
        layoutFull(view)
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.representation(using: .png, properties: [:])
    }

    /// 分页 PDF。页宽 = 视图宽，页高按 A4 纵横比缩放；
    /// 分页点落在行缝上（枚举行 fragment 的底边），不把一行切成两半。
    static func pdf(_ rendered: Rendered, options: Options) -> Data? {
        let view = makeTextView(rendered, options: options)
        let totalHeight = layoutFull(view)
        guard totalHeight > 0,
              let manager = view.layoutManager, manager.numberOfGlyphs > 0 else { return nil }

        let viewWidth = view.bounds.width
        let pageHeight = floor(viewWidth * (841.8 / 595.2))

        // 行缝（视图坐标）：每页在不超过页高的前提下尽量多装
        var seams: [CGFloat] = [0]
        manager.enumerateLineFragments(
            forGlyphRange: NSRange(location: 0, length: manager.numberOfGlyphs)
        ) { _, usedRect, _, _, _ in
            seams.append(usedRect.maxY + view.textContainerOrigin.y)
        }
        seams.append(totalHeight)

        // 分页指令的字符位置 → 视图坐标（所在行 fragment 的顶边）。
        // 连续的多个指令落在同一位置，去重；文档末尾的指令没有内容可起页，忽略。
        var forcedSeams: [CGFloat] = []
        let charCount = (view.textStorage?.length ?? 0)
        for location in rendered.pageBreaks where location > 0 && location < charCount {
            let glyph = manager.glyphIndexForCharacter(at: location)
            let lineRect = manager.lineFragmentUsedRect(forGlyphAt: glyph, effectiveRange: nil)
            let y = lineRect.minY + view.textContainerOrigin.y
            if forcedSeams.last != y { forcedSeams.append(y) }
        }

        let document = PDFDocument()
        var top: CGFloat = 0
        while top < totalHeight {
            let limit = top + pageHeight
            var bottom = min(limit, totalHeight)
            if limit < totalHeight,
               let seam = seams.last(where: { $0 <= limit && $0 > top }) {
                bottom = seam
            }
            // 强制分页优先于「尽量多装」：本页范围内有分页指令，就在第一个指令处收页
            if let forced = forcedSeams.first(where: { $0 > top && $0 <= bottom }) {
                bottom = forced
            }
            let rect = NSRect(x: 0, y: top, width: viewWidth, height: bottom - top)
            // dataWithPDF 是矢量输出（文字可选中可复制），不是位图截图
            let data = view.dataWithPDF(inside: rect)
            guard let single = PDFDocument(data: data),
                  let page = single.page(at: 0) else { return nil }
            document.insert(page, at: document.pageCount)
            top = bottom
        }
        return document.dataRepresentation()
    }

    // MARK: - 一步到文件

    /// ⌘⇧E 与 CLI `render` 共用的出口。格式由输出路径的扩展名决定。
    static func write(
        text: String,
        kind: FileKind,
        baseURL: URL?,
        to output: URL,
        options: Options
    ) throws {
        guard kind.isTextual else { throw ExportError.notTextual }

        let rendered = render(text: text, kind: kind, baseURL: baseURL, options: options)
        let ext = output.pathExtension.lowercased()
        let data: Data?
        switch ext {
        case "png": data = png(rendered, options: options)
        case "pdf": data = pdf(rendered, options: options)
        default: throw ExportError.unsupportedFormat(ext)
        }
        guard let data else { throw ExportError.encodeFailed }
        try data.write(to: output)
    }

    // MARK: - 文本系统（与预览同构）

    /// 复制 PreviewViewController 的文本系统三角（NSTextStorage + PreviewLayoutManager
    /// + NSTextContainer + PreviewTextView）：装饰绘制（引用竖线、标题细线、代码块底色）
    /// 都挂在 PreviewTextView/PreviewLayoutManager 上，换一套体系就丢了它们。
    private static func makeTextView(_ rendered: Rendered, options: Options) -> PreviewTextView {
        let storage = NSTextStorage()
        let layout = PreviewLayoutManager()
        let container = NSTextContainer(
            size: NSSize(width: options.width, height: CGFloat.greatestFiniteMagnitude)
        )
        container.lineFragmentPadding = 0
        container.widthTracksTextView = false
        storage.addLayoutManager(layout)
        layout.addTextContainer(container)

        let viewWidth = options.width + 56 // 与预览相同的水平内边距（28×2）
        let view = PreviewTextView(
            frame: NSRect(x: 0, y: 0, width: viewWidth, height: 100),
            textContainer: container
        )
        view.applyDefaults()
        view.isEditable = false
        view.maxContentWidth = options.width
        view.textContainerInset = NSSize(width: 28, height: 24)
        view.drawsBackground = true
        view.backgroundColor = rendered.backgroundColor
        if let dark = options.dark {
            // 钉住明暗：动态色（system 主题的语义色）按这个外观解析
            view.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        }
        view.textStorage?.setAttributedString(rendered.attributed)
        return view
    }

    /// 全文排版并把视图撑到内容全高，返回总高（含上下内边距）
    @discardableResult
    private static func layoutFull(_ view: PreviewTextView) -> CGFloat {
        guard let manager = view.layoutManager, let container = view.textContainer else { return 0 }
        manager.ensureLayout(for: container)
        let height = ceil(manager.usedRect(for: container).height) + 48
        view.setFrameSize(NSSize(width: view.bounds.width, height: max(height, 1)))
        manager.ensureLayout(for: container)
        return height
    }
}
