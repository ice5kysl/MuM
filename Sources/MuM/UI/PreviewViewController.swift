import AppKit
import PDFKit

/// 预览面板。同一个位置承载四种内容：渲染后的 Markdown/纯文本、图片、PDF、空状态。
///
/// 关键在于「原生」二字：渲染结果是一个真实的 NSTextView，因此文本选中、⌘F 查找、
/// 三指查词、朗读、辅助功能全部免费获得 —— 这些是 WKWebView 方案要一个个补回来的东西。
final class PreviewViewController: NSViewController {

    private let textScrollView = NSScrollView()
    private let textView = makePreviewTextView()

    private let imageContainer = NSView()
    private let imageView = NSImageView()

    private let pdfView = PDFView()

    private let messageContainer = NSView()
    private let messageIcon = NSImageView()
    private let messageTitle = NSTextField(labelWithString: "")
    private let messageSubtitle = NSTextField(labelWithString: "")

    /// 点链接时优先在 MuM 内部处理的回调（比如跳到另一个 Markdown 文件）
    var onOpenInternalLink: ((URL) -> Bool)?

    /// 预览用的文本视图。不叫 contentView 是为了不和 NSWindow.contentView 混淆。
    var previewTextView: PreviewTextView { textView }

    /// 应用阅读主题的纸色。
    /// 文本视图和它外面的滚动视图都要换 —— 只换一个的话，换纸色只会换一半。
    func applyReadingTheme(_ theme: MarkdownTheme) {
        textView.backgroundColor = theme.backgroundColor
        textScrollView.backgroundColor = theme.backgroundColor
        textView.needsDisplay = true
    }

    // MARK: - 生命周期

    override func loadView() {
        view = NSView()
        view.wantsLayer = true

        setupText()
        setupImage()
        setupPDF()
        setupMessage()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        showMessage(symbol: "doc.text.magnifyingglass", title: "MuM", subtitle: "从左侧点击一个文件开始")
    }

    // MARK: - 搭建

    private func setupText() {
        textView.applyDefaults()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.drawsBackground = true
        textView.backgroundColor = .textBackgroundColor
        textView.textContainerInset = NSSize(width: 28, height: 24)
        textView.isAutomaticLinkDetectionEnabled = false
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.linkTextAttributes = [
            .foregroundColor: NSColor.linkColor,
            .cursor: NSCursor.pointingHand,
        ]

        textScrollView.documentView = textView
        textScrollView.hasVerticalScroller = true
        textScrollView.hasHorizontalScroller = false
        textScrollView.autohidesScrollers = true
        textScrollView.drawsBackground = true
        textScrollView.backgroundColor = .textBackgroundColor

        pin(textScrollView)
    }

    private func setupImage() {
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageContainer.addSubview(imageView)
        NSLayoutConstraint.activate([
            imageView.leadingAnchor.constraint(equalTo: imageContainer.leadingAnchor, constant: 20),
            imageView.trailingAnchor.constraint(equalTo: imageContainer.trailingAnchor, constant: -20),
            imageView.topAnchor.constraint(equalTo: imageContainer.topAnchor, constant: 20),
            imageView.bottomAnchor.constraint(equalTo: imageContainer.bottomAnchor, constant: -20),
        ])
        pin(imageContainer)
        imageContainer.isHidden = true
    }

    private func setupPDF() {
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        pdfView.displayDirection = .vertical
        pin(pdfView)
        pdfView.isHidden = true
    }

    private func setupMessage() {
        messageIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 34, weight: .light)
        messageIcon.contentTintColor = .tertiaryLabelColor
        messageIcon.translatesAutoresizingMaskIntoConstraints = false

        messageTitle.font = .systemFont(ofSize: 17, weight: .semibold)
        messageTitle.textColor = .secondaryLabelColor
        messageTitle.alignment = .center

        messageSubtitle.font = .systemFont(ofSize: 12)
        messageSubtitle.textColor = .tertiaryLabelColor
        messageSubtitle.alignment = .center
        messageSubtitle.lineBreakMode = .byWordWrapping
        messageSubtitle.maximumNumberOfLines = 4

        let stack = NSStackView(views: [messageIcon, messageTitle, messageSubtitle])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.setCustomSpacing(14, after: messageIcon)
        stack.translatesAutoresizingMaskIntoConstraints = false

        messageContainer.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: messageContainer.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: messageContainer.centerYAnchor),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 320),
        ])

        pin(messageContainer)
    }

    private func pin(_ subview: NSView) {
        subview.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(subview)
        NSLayoutConstraint.activate([
            subview.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            subview.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            subview.topAnchor.constraint(equalTo: view.topAnchor),
            subview.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    private func showOnly(_ target: NSView) {
        for candidate in [textScrollView, imageContainer, pdfView, messageContainer] {
            candidate.isHidden = (candidate !== target)
        }
    }

    // MARK: - 内容切换

    func show(attributed: NSAttributedString, preservingScroll: Bool) {
        showOnly(textScrollView)

        let savedOrigin = preservingScroll ? textScrollView.contentView.bounds.origin : .zero
        let savedFraction: CGFloat? = preservingScroll ? scrollFraction() : nil

        textView.textStorage?.setAttributedString(attributed)

        if let savedFraction {
            restoreScrollFraction(savedFraction)
        } else {
            textScrollView.contentView.scroll(to: savedOrigin)
            textView.scrollToBeginningOfDocument(nil)
        }
        textScrollView.reflectScrolledClipView(textScrollView.contentView)
    }

    func show(image: NSImage) {
        showOnly(imageContainer)
        imageView.image = image
    }

    func show(pdf url: URL) {
        showOnly(pdfView)
        pdfView.document = PDFDocument(url: url)
    }

    func showMessage(symbol: String, title: String, subtitle: String = "") {
        showOnly(messageContainer)
        messageIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        messageTitle.stringValue = title
        messageSubtitle.stringValue = subtitle
        messageSubtitle.isHidden = subtitle.isEmpty
    }

    // MARK: - 滚动同步

    /// 返回 0…1 的滚动进度，用于在重新渲染后保持阅读位置
    func scrollFraction() -> CGFloat {
        let clip = textScrollView.contentView
        let documentHeight = textView.frame.height
        let visibleHeight = clip.bounds.height
        let scrollable = documentHeight - visibleHeight
        guard scrollable > 1 else { return 0 }
        return min(max(clip.bounds.origin.y / scrollable, 0), 1)
    }

    func restoreScrollFraction(_ fraction: CGFloat) {
        let clip = textScrollView.contentView
        textView.layoutManager?.ensureLayout(for: textView.textContainer!)
        let documentHeight = textView.frame.height
        let scrollable = max(documentHeight - clip.bounds.height, 0)
        let y = scrollable * fraction
        clip.scroll(to: NSPoint(x: 0, y: y))
        textScrollView.reflectScrolledClipView(clip)
    }

    func scrollToTop() {
        textView.scrollToBeginningOfDocument(nil)
    }

    /// 按行号比例滚动到指定位置（编辑器滚动时联动预览）
    func scrollToFractionFromEditor(_ fraction: CGFloat) {
        restoreScrollFraction(fraction)
    }

    var isShowingText: Bool { !textScrollView.isHidden }
}

// MARK: - 链接

extension PreviewViewController: NSTextViewDelegate {

    func textView(_ textView: NSTextView, clickedOnLink link: Any, at charIndex: Int) -> Bool {
        let url: URL?
        if let direct = link as? URL {
            url = direct
        } else if let string = link as? String {
            url = URL(string: string)
        } else {
            url = nil
        }

        guard let url else { return false }

        // 相对路径的 Markdown 链接优先在 MuM 里打开，读文档时不用离开应用
        if url.isFileURL, let handler = onOpenInternalLink, handler(url) {
            return true
        }

        NSWorkspace.shared.open(url)
        return true
    }
}

// MARK: - 构造预览用的文本系统

/// 预览的文本视图用自定义的 layout manager —— 代码块底色要在文字**下方**自己画，
/// 默认的 `NSLayoutManager` 没有这个钩子之外的余地（详见 `PreviewLayoutManager`）。
///
/// 文本系统必须整套自建：`NSLayoutManager` / `NSTextContainer` / `NSTextStorage`
/// 是绑死的三角，没法在 `PreviewTextView(frame:)` 建好之后替换其中一环。
private func makePreviewTextView() -> PreviewTextView {
    let storage = NSTextStorage()
    let layout = PreviewLayoutManager()
    let container = NSTextContainer(
        size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    )
    container.lineFragmentPadding = 0
    container.widthTracksTextView = false

    storage.addLayoutManager(layout)
    layout.addTextContainer(container)

    return PreviewTextView(frame: .zero, textContainer: container)
}

// MARK: - 带装饰绘制的预览文本视图

/// 在 NSTextView 之上手工绘制 Markdown 的「结构性装饰」：引用块竖线、分隔线、
/// 标题下的细线。这些在 NSAttributedString 里没有对应能力，但用 layout manager
/// 拿到段落矩形后直接画，比嵌套 NSTextBlock 或改用 Web 视图都更轻。
final class PreviewTextView: NSTextView {

    /// 正文最大宽度，超出后居中留白
    var maxContentWidth: CGFloat = 780 {
        didSet { updateContainerWidth() }
    }

    /// 由 PreviewViewController 在取到实例后调用。
    /// 不放在 init 里是因为 NSTextView 的指定初始化器是 `init(frame:textContainer:)`，
    /// 子类重写它容易和 NSTextView 内部构造文本系统的顺序打架。
    func applyDefaults() {
        isVerticallyResizable = true
        isHorizontallyResizable = false
        autoresizingMask = [.width]
        maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textContainer?.widthTracksTextView = false
        textContainer?.lineFragmentPadding = 0
        updateContainerWidth()
    }

    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        updateContainerWidth()
    }

    private func updateContainerWidth() {
        guard let textContainer else { return }
        let available = max(200, bounds.width - textContainerInset.width * 2)
        let width = min(available, maxContentWidth)
        if abs(textContainer.size.width - width) > 0.5 {
            textContainer.size = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        }
    }

    /// 内容窄于可用宽度时整体居中
    override var textContainerOrigin: NSPoint {
        let inset = textContainerInset
        let containerWidth = textContainer?.size.width ?? 0
        let available = bounds.width - inset.width * 2
        let x = inset.width + max(0, (available - containerWidth) / 2)
        return NSPoint(x: x, y: inset.height)
    }

    // MARK: - 绘制装饰

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        drawDecorations()
    }

    private func drawDecorations() {
        guard let layoutManager, let textContainer, let textStorage, textStorage.length > 0 else { return }

        let glyphRange = layoutManager.glyphRange(forBoundingRect: bounds, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard charRange.length > 0 else { return }

        let origin = textContainerOrigin
        let contentWidth = textContainer.size.width

        textStorage.enumerateAttributes(in: charRange, options: []) { attributes, range, _ in
            // 段落末尾的换行符在排版上属于下一行，算进矩形会让装饰整体下移一行
            let rect = self.boundingRect(for: self.withoutTrailingNewlines(range), origin: origin)
            guard rect.height > 0 else { return }

            if let depth = attributes[.mumQuoteDepth] as? Int, depth > 0 {
                let color = (attributes[.mumQuoteColor] as? NSColor) ?? .separatorColor
                let style = attributes[.paragraphStyle] as? NSParagraphStyle
                color.setFill()
                // 向下多画一个段后间距，多段引用的竖线才能连成一条
                let bleed = style?.paragraphSpacing ?? 0
                let x = origin.x + CGFloat(depth - 1) * 18
                NSRect(x: x, y: rect.minY, width: 3, height: rect.height + bleed).fill()
            }

            if attributes[.mumHorizontalRule] != nil {
                NSColor.separatorColor.setFill()
                NSRect(x: origin.x, y: rect.midY, width: contentWidth, height: 1).fill()
            }

            if attributes[.mumHeadingRule] != nil {
                NSColor.separatorColor.withAlphaComponent(0.6).setFill()
                NSRect(x: origin.x, y: rect.maxY - 2, width: contentWidth, height: 1).fill()
            }
        }
    }

    /// 去掉范围末尾的换行符
    private func withoutTrailingNewlines(_ range: NSRange) -> NSRange {
        guard let textStorage else { return range }
        let units = Array(textStorage.string.utf16)
        var length = range.length
        while length > 0, range.location + length - 1 < units.count, units[range.location + length - 1] == 0x0A {
            length -= 1
        }
        return length > 0 ? NSRange(location: range.location, length: length) : range
    }

    private func boundingRect(for charRange: NSRange, origin: NSPoint) -> NSRect {
        guard let layoutManager, let textContainer else { return .zero }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: charRange, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += origin.x
        rect.origin.y += origin.y
        return rect
    }
}
