import AppKit
import PDFKit

/// 预览面板。同一个位置承载四种内容：渲染后的 Markdown/纯文本、图片、PDF、空状态。
///
/// 关键在于「原生」二字：渲染结果是一个真实的 NSTextView，因此文本选中、⌘F 查找、
/// 三指查词、朗读、辅助功能全部免费获得 —— 这些是 WKWebView 方案要一个个补回来的东西。
final class PreviewViewController: NSViewController {

    private let findBar = PreviewFindBar()
    private let textScrollView = NSScrollView()
    private var findMatches: [NSRange] = []
    private var currentMatchIndex = 0
    private var findBarHeight: NSLayoutConstraint!
    private var isFindBarVisible = false
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

    // MARK: - 查找

    /// ⌘F：显示查找条并聚焦。已经显示时只重新聚焦。
    func showFindBar() {
        guard textScrollView.superview != nil else { return }
        if !isFindBarVisible {
            isFindBarVisible = true
            findBarHeight.constant = 34
            findBar.isHidden = false
            view.needsLayout = true
        }
        findBar.focus()
    }

    /// Esc：关闭查找条并清掉所有高亮
    func hideFindBar() {
        guard isFindBarVisible else { return }
        isFindBarVisible = false
        findBarHeight.constant = 0
        findBar.isHidden = true
        findMatches = []
        clearHighlights()
        view.window?.makeFirstResponder(textView)
    }

    var isFinding: Bool { isFindBarVisible }

    // MARK: - 大纲

    private var outline: [MarkdownRenderer.OutlineItem] = []
    private var outlinePopover: NSPopover?

    /// 每次重排后由窗口控制器写入。
    /// 大纲的位置（字符下标）是针对**当前这份渲染结果**的，重排后必须换新的，
    /// 否则跳转会落到错的地方。
    func setOutline(_ items: [MarkdownRenderer.OutlineItem]) {
        outline = items
    }

    var hasOutline: Bool { !outline.isEmpty }

    /// 诊断用：大纲收到了什么
    var debugOutlineSummary: String {
        outline.isEmpty
            ? "空"
            : "\(outline.count) 条：" + outline.prefix(4).map { "H\($0.level)@\($0.location) \($0.title)" }.joined(separator: " | ")
    }

    func showOutline(from pane: NSView) {
        guard !outline.isEmpty else { return }
        if let existing = outlinePopover, existing.isShown {
            existing.performClose(nil)
            return
        }

        let list = PreviewOutlineView(items: outline)
        list.onSelect = { [weak self] location in
            self?.outlinePopover?.performClose(nil)
            self?.scrollToCharacter(location)
        }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = list
        popover.contentSize = list.preferredContentSize
        // 锚在内容区顶栏左端，向下弹出 —— 大纲是"从这里往下有什么"的地图，
        // 贴着正文上沿出现最自然
        let anchor = NSRect(x: 24, y: pane.bounds.height - 30, width: 1, height: 1)
        popover.show(relativeTo: anchor, of: pane, preferredEdge: .minY)
        outlinePopover = popover
    }

    private func scrollToCharacter(_ location: Int) {
        guard let manager = textView.layoutManager, let container = textView.textContainer,
              location < (textView.string as NSString).length else { return }
        let range = NSRange(location: location, length: 1)
        let glyphRange = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        let rect = manager.boundingRect(forGlyphRange: glyphRange, in: container)
        // 顶端留一点余量，标题不要贴着上沿
        textView.scrollToVisible(
            rect.offsetBy(dx: 0, dy: textView.textContainerOrigin.y).insetBy(dx: 0, dy: -16)
        )
    }

    /// 诊断用：离屏快照里没法敲键盘，用它触发一次查找
    func debugRunFind(_ query: String) {
        showFindBar()
        findBar.setQuery(query)
        runFind(query)
    }

    func findNext() { step(by: 1) }
    func findPrevious() { step(by: -1) }

    /// 全局搜索定位：显示查找条、填入查询、直接跳到文件里第 occurrence 处命中。
    /// 与 ⌘F 的手动查找同一条路径（同一套高亮），只是起点由搜索结果指定。
    func reveal(query: String, occurrence: Int) {
        showFindBar()
        findBar.setQuery(query)
        runFind(query)
        guard !findMatches.isEmpty else { return }
        // 渲染文本与源文件的命中数可能不一致（Markdown 语法字符不进渲染结果），
        // occurrence 越界就落在最后一处 —— 落错一处比什么都不显示好
        currentMatchIndex = min(max(occurrence - 1, 0), findMatches.count - 1)
        highlightMatches()
        scrollToCurrentMatch()
    }

    private func step(by delta: Int) {
        guard !findMatches.isEmpty else { return }
        currentMatchIndex = (currentMatchIndex + delta + findMatches.count) % findMatches.count
        highlightMatches()
        scrollToCurrentMatch()
    }

    private func runFind(_ query: String) {
        clearHighlights()
        findMatches = []
        currentMatchIndex = 0

        guard !query.isEmpty else {
            findBar.update(current: 0, total: 0)
            return
        }

        let haystack = textView.string as NSString
        var searchRange = NSRange(location: 0, length: haystack.length)
        while searchRange.length > 0 {
            let found = haystack.range(
                of: query,
                options: [.caseInsensitive, .diacriticInsensitive],
                range: searchRange
            )
            guard found.location != NSNotFound else { break }
            findMatches.append(found)
            let next = found.location + max(found.length, 1)
            guard next < haystack.length else { break }
            searchRange = NSRange(location: next, length: haystack.length - next)
        }

        // 命中的位置从当前滚动处开始找，比永远从第一处开始符合直觉
        if let nearest = nearestMatchToViewport() { currentMatchIndex = nearest }
        highlightMatches()
        scrollToCurrentMatch()
    }

    private func nearestMatchToViewport() -> Int? {
        let top = textScrollView.contentView.bounds.origin.y
        guard let manager = textView.layoutManager, let container = textView.textContainer else { return nil }
        for (index, range) in findMatches.enumerated() {
            let glyphRange = manager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            let rect = manager.boundingRect(forGlyphRange: glyphRange, in: container)
            if rect.minY + textView.textContainerOrigin.y >= top { return index }
        }
        return findMatches.isEmpty ? nil : findMatches.count - 1
    }

    private func highlightMatches() {
        guard let storage = textView.textStorage else { return }
        storage.removeAttribute(.mumFindMatch, range: NSRange(location: 0, length: storage.length))
        for (index, range) in findMatches.enumerated() {
            guard range.location + range.length <= storage.length else { continue }
            storage.addAttribute(.mumFindMatch, value: index == currentMatchIndex ? 1 : 0, range: range)
        }
        findBar.update(current: findMatches.isEmpty ? 0 : currentMatchIndex + 1, total: findMatches.count)
        textView.needsDisplay = true
    }

    private func clearHighlights() {
        guard let storage = textView.textStorage, storage.length > 0 else { return }
        storage.removeAttribute(.mumFindMatch, range: NSRange(location: 0, length: storage.length))
        textView.needsDisplay = true
    }

    private func scrollToCurrentMatch() {
        guard findMatches.indices.contains(currentMatchIndex),
              let manager = textView.layoutManager,
              let container = textView.textContainer else { return }
        let glyphRange = manager.glyphRange(forCharacterRange: findMatches[currentMatchIndex], actualCharacterRange: nil)
        let rect = manager.boundingRect(forGlyphRange: glyphRange, in: container)
        textView.scrollToVisible(rect.offsetBy(dx: 0, dy: textView.textContainerOrigin.y).insetBy(dx: 0, dy: -60))
    }

    /// 应用阅读主题的纸色。
    /// 文本视图和它外面的滚动视图都要换 —— 只换一个的话，换纸色只会换一半。
    func applyReadingTheme(_ theme: MarkdownTheme) {
        textView.backgroundColor = theme.backgroundColor
        textScrollView.backgroundColor = theme.backgroundColor
        if let manager = textView.layoutManager as? PreviewLayoutManager {
            manager.findMatchColor = theme.findMatchColor
            manager.currentFindMatchColor = theme.currentFindMatchColor
        }
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
        // 链接点击走 clickedOnLink（内部打开 .md，外部链接交系统）——
        // 之前漏了这条线，代理方法写了却从没接过，点击全走了系统默认
        textView.delegate = self
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

        // 查找条贴在顶部，高度约束 0 = 收起；滚动视图在它下面。
        // 做成内容区自己的一条而不是独立浮层：查找是阅读的辅助动作，
        // 不该独占窗口，也不该遮住正文。
        findBar.translatesAutoresizingMaskIntoConstraints = false
        findBar.isHidden = true
        findBar.onQueryChanged = { [weak self] query in self?.runFind(query) }
        findBar.onNext = { [weak self] in self?.findNext() }
        findBar.onPrevious = { [weak self] in self?.findPrevious() }
        findBar.onClose = { [weak self] in self?.hideFindBar() }
        view.addSubview(findBar)

        findBarHeight = findBar.heightAnchor.constraint(equalToConstant: 0)
        textScrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textScrollView)

        NSLayoutConstraint.activate([
            findBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            findBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            findBar.topAnchor.constraint(equalTo: view.topAnchor),
            findBarHeight,

            textScrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            textScrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            textScrollView.topAnchor.constraint(equalTo: findBar.bottomAnchor),
            textScrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
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
        // 切换到图片 / PDF / 提示页时收起查找条 —— 那些视图里没有可查找的文本
        if target !== textScrollView, isFindBarVisible {
            isFindBarVisible = false
            findBarHeight.constant = 0
            findBar.isHidden = true
        }
    }

    // MARK: - 内容切换

    /// 渐进渲染的填充片：拼到 textStorage 末尾。
    /// 追加发生在文档尾部，不重排也不移动已显示的部分，用户看到的首屏保持不动。
    func append(attributed: NSAttributedString) {
        cachedDocumentHeight = nil
        textView.textStorage?.append(attributed)
    }

    /// - Parameter restoreFraction: 打开**另一个文件**时传它保存过的位置；
    ///   传 nil 表示这是一次重排（同一文件，比如边打字边渲染），保持当前滚动不动。
    func show(attributed: NSAttributedString, restoreFraction: CGFloat?) {
        showOnly(textScrollView)
        LaunchTimer.mark("    show: showOnly 完成")

        // 重排只需要"别跳"：记住绝对滚动位置就够，不需要文档高度 ——
        // scrollFraction() 会 ensureLayout 整篇，打字时每 110ms 触发一次全量排版
        // （1MB 实测 ≈812ms），热路径上不能要。比例只在跨次打开时用
        // （文档可能变长变短），那时一次全量排版是值得的。
        let keptOrigin: NSPoint? = restoreFraction == nil ? textScrollView.contentView.bounds.origin : nil

        cachedDocumentHeight = nil
        textView.textStorage?.setAttributedString(attributed)
        LaunchTimer.mark("    show: setAttributedString 完成")

        if let restoreFraction, restoreFraction > 0.001 {
            restoreScrollFraction(restoreFraction)
        } else if let keptOrigin, keptOrigin.y > 0.5 {
            let clip = textScrollView.contentView
            clip.scroll(to: keptOrigin)
            textScrollView.reflectScrolledClipView(clip)
        } else {
            textView.scrollToBeginningOfDocument(nil)
        }
        LaunchTimer.mark("    show: 滚动定位完成")
        textScrollView.reflectScrolledClipView(textScrollView.contentView)

        // textStorage 被整个换掉了，查找高亮要重新套一遍
        if isFindBarVisible { runFind(findBar.query) }
        LaunchTimer.mark("    show: 完成")
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

    /// 文档总高度（含上下内边距）。
    ///
    /// **不能用 `textView.frame.height`** —— frame 要等一次布局才更新，
    /// 而这两个方法都在 `setAttributedString` 之后立刻调用，那时 frame 还是
    /// 上一个文档的。实测后果：恢复位置时算出的可滚动高度≈0（纹丝不动），
    /// 保存位置时算出的比例也永远偏小。
    /// 排版结果（`usedRect`）在 `ensureLayout` 之后立刻就是对的。
    ///
    /// 结果带缓存：`ensureLayout` 整篇是 O(文档) 的重操作（1MB ≈812ms），
    /// 而编辑器滚动联动会连续询问 —— 内容不变高度就不会变。
    /// 失效点：show()/append() 换内容、viewDidLayout() 改宽度。
    private var cachedDocumentHeight: CGFloat?

    private var documentHeight: CGFloat {
        if let cachedDocumentHeight { return cachedDocumentHeight }
        guard let manager = textView.layoutManager, let container = textView.textContainer else {
            return textView.frame.height
        }
        manager.ensureLayout(for: container)
        let height = manager.usedRect(for: container).height + textView.textContainerInset.height * 2
        cachedDocumentHeight = height
        return height
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        // 宽度变了要重新折行，缓存的高度作废
        cachedDocumentHeight = nil
    }

    /// 返回 0…1 的滚动进度。注意它会触发 documentHeight（首查时全量排版，有缓存）——
    /// 调用点限于：保存阅读位置、渐进填充完成后的「用户动过没有」判断。
    /// 打字重排保位置不需要它（show() 里记绝对 origin 就够）。
    func scrollFraction() -> CGFloat {
        let clip = textScrollView.contentView
        let scrollable = documentHeight - clip.bounds.height
        guard scrollable > 1 else { return 0 }
        return min(max(clip.bounds.origin.y / scrollable, 0), 1)
    }

    func restoreScrollFraction(_ fraction: CGFloat) {
        let clip = textScrollView.contentView
        let scrollable = max(documentHeight - clip.bounds.height, 0)
        clip.scroll(to: NSPoint(x: 0, y: scrollable * fraction))
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

    // **非连续排版**。TextKit 默认是连续排版：要排第 10000 行，得先把前 9999 行排完。
    // 大文档打开时因此会把整篇排一遍 —— 实测 1MB 的 markdown 排版就要 1 秒、
    // 5MB 要 9 秒（`--bench` 可复现），直接把"280 毫秒上屏"这个定位打穿。
    // 打开它之后，跳到某处只排到那处为止。
    layout.allowsNonContiguousLayout = true

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
        drawDecorations(in: dirtyRect)
    }

    private func drawDecorations(in dirtyRect: NSRect) {
        guard let layoutManager, let textContainer, let textStorage, textStorage.length > 0 else { return }

        let origin = textContainerOrigin
        // 只覆盖 dirtyRect 这一片（审计 R-2）：原先用整篇 bounds 取 glyphRange，
        // **每次绘制都把全文排版一遍**，`allowsNonContiguousLayout` 被完全架空 ——
        // 它就是 5MB 排版 9 秒的真凶。super.draw 本就已排版脏区，这里只是复用。
        // 装饰有少量出血（引用竖线向下延一个段后间距、标题线贴段落底），
        // 上下各放宽 24pt，免得滚动到边缘时缺线。
        let visible = dirtyRect
            .offsetBy(dx: -origin.x, dy: -origin.y)
            .insetBy(dx: 0, dy: -24)
        let glyphRange = layoutManager.glyphRange(forBoundingRect: visible, in: textContainer)
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard charRange.length > 0 else { return }

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
        // 直接按索引读，不许 Array(utf16) —— 那会把整篇文档复制一遍，
        // 而这里每个属性段都会调一次（大文档下就是 O(段数 × 全文)）
        let string = textStorage.string as NSString
        var length = range.length
        while length > 0, range.location + length - 1 < string.length,
              string.character(at: range.location + length - 1) == 0x0A {
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
