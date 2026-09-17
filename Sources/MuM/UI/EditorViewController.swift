import AppKit

/// 源码编辑区。
///
/// 这里是 MuM 唯一「重」交互的地方，所以细节值得抠：关掉全部智能替换（智能引号会把
/// `"` 变成 `"`，直接毁掉 Markdown 源码）、Tab 插入空格而不是跳焦点、回车自动延续
/// 列表标记 —— 写 Markdown 时最高频的三个动作都被接住了。
final class EditorViewController: NSViewController, NSTextViewDelegate {

    private let scrollView = NSScrollView()
    private let textView = EditorTextView(frame: .zero)

    /// 文本变化（用于标脏 + 刷新预览）
    var onTextChanged: ((String) -> Void)?
    /// 滚动（用于让预览跟随）
    var onScroll: ((CGFloat) -> Void)?

    private var isProgrammaticChange = false
    private var lineNumberRuler: LineNumberRulerView?
    private var editorFontSize: CGFloat = 13
    private var typewriterMode = false
    /// Tab 插入的空格数，由系统设置驱动
    private var indentWidth = 2

    // MARK: - 生命周期

    override func loadView() {
        view = NSView()
        setup()
    }

    private func setup() {
        textView.isRichText = false
        textView.isEditable = true
        textView.isSelectable = true
        textView.allowsUndo = true
        textView.usesFindBar = true
        textView.isIncrementalSearchingEnabled = true
        textView.font = .monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.textColor = .textColor
        textView.backgroundColor = .textBackgroundColor
        textView.drawsBackground = true
        textView.textContainerInset = NSSize(width: 18, height: 16)
        textView.delegate = self

        // Markdown 源码里这些「贴心功能」全是灾难
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.smartInsertDeleteEnabled = false

        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.lineFragmentPadding = 0

        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = true
        scrollView.backgroundColor = .textBackgroundColor

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: view.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        // 滚动联动预览
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(boundsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    // MARK: - 对外接口

    var text: String { textView.string }

    func setText(_ text: String, resetUndo: Bool = true) {
        isProgrammaticChange = true
        textView.string = text
        textView.setSelectedRange(NSRange(location: 0, length: 0))
        if resetUndo {
            textView.undoManager?.removeAllActions()
        }
        isProgrammaticChange = false
        textView.scrollToBeginningOfDocument(nil)
        textView.needsDisplay = true
        lineNumberRuler?.needsDisplay = true
    }

    func setEditable(_ editable: Bool) {
        textView.isEditable = editable
    }

    // MARK: - 应用偏好

    func apply(settings: MuMSettings) {
        editorFontSize = settings.editorFontSize
        typewriterMode = settings.typewriterMode
        indentWidth = settings.indentWidth
        textView.font = .monospacedSystemFont(ofSize: settings.editorFontSize, weight: .regular)
        textView.showsCurrentLineHighlight = settings.highlightsCurrentLine
        applyLineNumbers(visible: settings.showsLineNumbers)
        // 字号变了行高就变了，行号和当前行高亮都得重画
        textView.needsDisplay = true
        lineNumberRuler?.needsDisplay = true
        centerCaretIfNeeded()
    }

    /// 打字机模式：让光标所在行始终停在编辑区中间。
    ///
    /// 写长文时视线不用跟着光标往下爬 —— 屏幕上光标的位置是恒定的。
    private func centerCaretIfNeeded() {
        guard typewriterMode,
              let layoutManager = textView.layoutManager,
              let container = textView.textContainer else { return }

        let content = textView.string as NSString
        let caret = min(textView.selectedRange().location, content.length)
        let lineRange = content.lineRange(for: NSRange(location: caret, length: 0))
        let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
        let rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: container)

        let clip = scrollView.contentView
        let desired = rect.midY + textView.textContainerInset.height - clip.bounds.height / 2
        let maxOffset = max(0, textView.frame.height - clip.bounds.height)
        let target = min(max(desired, 0), maxOffset)

        guard abs(clip.bounds.origin.y - target) > 0.5 else { return }
        clip.scroll(to: NSPoint(x: 0, y: target))
        scrollView.reflectScrolledClipView(clip)
    }

    private func applyLineNumbers(visible: Bool) {
        guard visible else {
            scrollView.rulersVisible = false
            return
        }

        let ruler = lineNumberRuler ?? LineNumberRulerView(textView: textView, fontSize: editorFontSize)
        ruler.updateFontSize(editorFontSize)
        lineNumberRuler = ruler

        scrollView.verticalRulerView = ruler
        scrollView.hasVerticalRuler = true
        scrollView.rulersVisible = true
        ruler.needsDisplay = true
    }

    func focus() {
        view.window?.makeFirstResponder(textView)
    }

    /// 编辑器滚动进度 0…1
    func scrollFraction() -> CGFloat {
        let clip = scrollView.contentView
        let scrollable = textView.frame.height - clip.bounds.height
        guard scrollable > 1 else { return 0 }
        return min(max(clip.bounds.origin.y / scrollable, 0), 1)
    }

    // MARK: - NSTextViewDelegate

    func textViewDidChangeSelection(_ notification: Notification) {
        centerCaretIfNeeded()
    }

    func textDidChange(_ notification: Notification) {
        lineNumberRuler?.needsDisplay = true
        centerCaretIfNeeded()
        guard !isProgrammaticChange else { return }
        onTextChanged?(textView.string)
    }

    @objc private func boundsDidChange() {
        // 行号栏固定不动，滚动时要手动重画
        lineNumberRuler?.needsDisplay = true
        onScroll?(scrollFraction())
    }

    // MARK: - 键位

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        if commandSelector == #selector(NSResponder.insertNewline(_:)) {
            return handleNewline(textView)
        }
        if commandSelector == #selector(NSResponder.insertTab(_:)) {
            // 在编辑器里 Tab 永远插入缩进，不跳焦点
            textView.insertText(String(repeating: " ", count: indentWidth), replacementRange: textView.selectedRange())
            return true
        }
        if commandSelector == #selector(NSResponder.insertBacktab(_:)) {
            outdent(textView)
            return true
        }
        return false
    }

    /// 回车自动延续列表标记；在空列表项上回车则退出列表
    private func handleNewline(_ textView: NSTextView) -> Bool {
        let ns = textView.string as NSString
        let caret = textView.selectedRange()
        let lineRange = ns.lineRange(for: NSRange(location: caret.location, length: 0))
        var line = ns.substring(with: lineRange)
        if line.hasSuffix("\n") { line.removeLast() }

        guard let parsed = ListMarker.parse(line) else {
            textView.insertNewlineIgnoringFieldEditor(nil)
            return true
        }

        // 列表项里没有内容 → 回车退出列表，去掉标记
        if parsed.content.trimmingCharacters(in: .whitespaces).isEmpty {
            textView.insertText("\n", replacementRange: lineRange)
            return true
        }

        let insertion = "\n\(parsed.indent)\(parsed.nextMarker) \(parsed.checkbox)"
        textView.insertText(insertion, replacementRange: caret)
        return true
    }

    private func outdent(_ textView: NSTextView) {
        let ns = textView.string as NSString
        let caret = textView.selectedRange()
        let lineRange = ns.lineRange(for: NSRange(location: caret.location, length: 0))
        let line = ns.substring(with: lineRange)

        let removable = line.hasPrefix("  ") ? 2 : (line.hasPrefix(" ") ? 1 : 0)
        guard removable > 0 else { return }

        let target = NSRange(location: lineRange.location, length: removable)
        textView.insertText("", replacementRange: target)
    }
}

// MARK: - 列表标记解析

/// 从一行 Markdown 里解析出列表结构，供回车续行使用。
struct ListMarker {
    let indent: String
    let marker: String
    let checkbox: String
    let content: String

    var nextMarker: String {
        // 有序列表递增，其余保持原样
        let digits = marker.prefix { $0.isNumber }
        guard !digits.isEmpty, let value = Int(digits) else { return marker }
        let separator = marker.hasSuffix(")") ? ")" : "."
        return "\(value + 1)\(separator)"
    }

    private static let regex = try? NSRegularExpression(
        pattern: #"^([ \t]*)([-*+]|\d+[.)])[ \t]+(\[[ xX]\][ \t]+)?"#
    )

    static func parse(_ line: String) -> ListMarker? {
        guard let regex else { return nil }
        let ns = line as NSString
        guard let match = regex.firstMatch(in: line, range: NSRange(location: 0, length: ns.length)) else {
            return nil
        }

        let indent = ns.substring(with: match.range(at: 1))
        let marker = ns.substring(with: match.range(at: 2))
        let checkbox = match.range(at: 3).location == NSNotFound ? "" : "[ ] "
        let content = ns.substring(from: match.range.length)

        return ListMarker(indent: indent, marker: marker, checkbox: checkbox, content: content)
    }
}

// MARK: - 编辑区文本视图

/// 多一个「当前行」高亮。纯视觉，但长时间写作时定位光标便宜很多。
final class EditorTextView: NSTextView {

    /// 是否高亮光标所在行（设置项）
    var showsCurrentLineHighlight = true {
        didSet { needsDisplay = true }
    }

    private var highlightedLine: NSRect = .zero

    override func drawBackground(in rect: NSRect) {
        super.drawBackground(in: rect)
        guard showsCurrentLineHighlight else { return }

        let lineRect = currentLineRect()
        highlightedLine = lineRect
        guard rect.intersects(lineRect) else { return }

        NSColor.selectedContentBackgroundColor.withAlphaComponent(0.07).setFill()
        lineRect.fill()
    }

    override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
        let previous = highlightedLine
        super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
        guard !stillSelecting else { return }

        let current = currentLineRect()
        highlightedLine = current
        setNeedsDisplay(previous.union(current).insetBy(dx: -4, dy: -4))
    }

    private func currentLineRect() -> NSRect {
        guard let layoutManager, let textContainer else { return .zero }
        let caret = selectedRange()
        guard caret.location <= (string as NSString).length else { return .zero }

        let lineRange = (string as NSString).lineRange(for: NSRange(location: caret.location, length: 0))
        let glyphRange = layoutManager.glyphRange(forCharacterRange: lineRange, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        guard rect.height > 0 else { return .zero }

        rect.origin.x = 0
        rect.size.width = bounds.width
        rect.origin.y += textContainerOrigin.y
        return rect
    }
}
