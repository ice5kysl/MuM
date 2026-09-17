import AppKit

/// 源码编辑区的行号栏。
///
/// 只给**段落的起始行**编号，软换行产生的续行不编号 —— 这和所有编辑器的行为一致，
/// 也是"行号"这个词在直觉上的含义。
///
/// 行号栏贴在滚动视图左侧固定不动，所以滚动时必须重画：它不像文档视图那样自己滚。
final class LineNumberRulerView: NSRulerView {

    private var numberFont: NSFont

    init(textView: NSTextView, fontSize: CGFloat) {
        self.numberFont = Self.makeFont(for: fontSize)
        super.init(scrollView: textView.enclosingScrollView, orientation: .verticalRuler)
        clientView = textView
        ruleThickness = 44
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func makeFont(for fontSize: CGFloat) -> NSFont {
        .monospacedDigitSystemFont(ofSize: max(fontSize - 2, 9), weight: .regular)
    }

    func updateFontSize(_ fontSize: CGFloat) {
        numberFont = Self.makeFont(for: fontSize)
        needsDisplay = true
    }

    override func drawHashMarksAndLabels(in rect: NSRect) {
        guard let textView = clientView as? NSTextView,
              let layoutManager = textView.layoutManager,
              let textContainer = textView.textContainer else { return }

        MuMDesign.paneBackground.setFill()
        bounds.fill()

        let content = textView.string as NSString
        let glyphRange = layoutManager.glyphRange(
            forBoundingRect: textView.visibleRect,
            in: textContainer
        )
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)

        // 可见范围之前有多少个换行，决定首行的编号
        var lineNumber = 1
        let scanEnd = min(charRange.location, content.length)
        var scan = 0
        while scan < scanEnd {
            if content.character(at: scan) == 0x0A { lineNumber += 1 }
            scan += 1
        }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: numberFont,
            .foregroundColor: MuMDesign.tertiaryText,
        ]
        let inset = textView.textContainerInset

        var glyphIndex = glyphRange.location
        while glyphIndex < NSMaxRange(glyphRange) {
            var fragmentRange = NSRange()
            let fragment = layoutManager.lineFragmentRect(forGlyphAt: glyphIndex, effectiveRange: &fragmentRange)
            let charIndex = layoutManager.characterIndexForGlyph(at: fragmentRange.location)

            let isParagraphStart = charIndex == 0
                || (charIndex - 1 < content.length && content.character(at: charIndex - 1) == 0x0A)

            if isParagraphStart {
                let label = "\(lineNumber)" as NSString
                let size = label.size(withAttributes: attributes)
                let y = fragment.minY + inset.height + (fragment.height - size.height) / 2
                label.draw(
                    at: NSPoint(x: ruleThickness - size.width - 8, y: y),
                    withAttributes: attributes
                )
                lineNumber += 1
            }

            glyphIndex = NSMaxRange(fragmentRange)
        }
    }
}
