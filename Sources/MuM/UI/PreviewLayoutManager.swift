import AppKit

/// 在文字**之下**绘制块级装饰的布局管理器。
///
/// 只做一件事：给代码块铺底色。
///
/// 为什么不用 NSAttributedString 的 `.backgroundColor`：TextKit 填背景时，
/// **首行**从 `firstLineHeadIndent` 起算，**续行**却从行片段原点起算（忽略 `headIndent`）。
/// 于是续行的底色向左多铺了一个缩进量，代码块左上角就缺了一角。
/// 试过用 `NSTextBlock` 代替 —— 纯 `NSTextBlock`（不像 `NSTextTable`）不会自己绘制底色，
/// 结果整块底色都没了。
///
/// 所以自己画：`drawBackground(forGlyphRange:at:)` 是 TextKit 绘制文字内容之前必经的钩子，
/// 在这里填色天然位于文字下方，而且从容器左缘铺到右缘、上下各留一点内边距，完全可控。
///
/// 注意这个钩子的绘图上下文**被裁剪在文本容器内部** —— 想画到容器左侧的留白里
/// （比如预览区的行号），得去 `PreviewTextView.draw` 里画，这里画会被裁掉。
final class PreviewLayoutManager: NSLayoutManager {

    /// 底色上下各外扩多少，做出内边距
    private let verticalPadding: CGFloat = 6

    /// 查找命中的底色。和代码块底色走同一套机制 —— 都在文字下方，
    /// 所以不会盖住字形，也不和行内代码的 `.backgroundColor` 打架。
    var findMatchColor = NSColor.systemYellow.withAlphaComponent(0.30)
    var currentFindMatchColor = NSColor.systemOrange.withAlphaComponent(0.55)

    override func drawBackground(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        drawCodeBlockBackgrounds(forGlyphRange: glyphsToShow, at: origin)
        drawFindMatches(forGlyphRange: glyphsToShow, at: origin)
        super.drawBackground(forGlyphRange: glyphsToShow, at: origin)
    }

    private func drawFindMatches(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let textStorage, let container = textContainers.first else { return }

        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        guard charRange.length > 0 else { return }

        textStorage.enumerateAttribute(.mumFindMatch, in: charRange, options: []) { value, range, _ in
            guard let rank = value as? Int else { return }

            let glyphRange = self.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
            guard glyphRange.length > 0 else { return }

            var rect = self.boundingRect(forGlyphRange: glyphRange, in: container)
            // 用行片段的高度，铺满整行 —— 只按字形包围盒画会是一条细带，很难看见。
            // （跨行的命中会偏矮，但那种情况很少，先用简单做法。）
            let line = self.lineFragmentRect(forGlyphAt: glyphRange.location, effectiveRange: nil)
            rect.origin.y = line.minY
            rect.size.height = line.height
            rect.origin.x += origin.x
            rect.origin.y += origin.y

            (rank == 1 ? self.currentFindMatchColor : self.findMatchColor).setFill()
            rect.fill()
        }
    }

    private func drawCodeBlockBackgrounds(forGlyphRange glyphsToShow: NSRange, at origin: NSPoint) {
        guard let textStorage, let container = textContainers.first else { return }

        let charRange = characterRange(forGlyphRange: glyphsToShow, actualGlyphRange: nil)
        guard charRange.length > 0 else { return }

        // 只按这一个属性枚举，整段代码块会作为一个 range 返回 ——
        // 用 enumerateAttributes 的话每个语法高亮 token 都会拆成一段，白白重复填色。
        textStorage.enumerateAttribute(.mumCodeBlock, in: charRange, options: []) { value, range, _ in
            guard let color = value as? NSColor else { return }

            let trimmed = self.withoutTrailingNewlines(range, in: textStorage)
            guard trimmed.length > 0 else { return }

            let glyphRange = self.glyphRange(forCharacterRange: trimmed, actualCharacterRange: nil)
            var rect = self.boundingRect(forGlyphRange: glyphRange, in: container)
            rect.origin.x += origin.x
            rect.origin.y += origin.y

            color.setFill()
            NSRect(
                x: origin.x,
                y: rect.minY - self.verticalPadding,
                width: container.size.width,
                height: rect.height + self.verticalPadding * 2
            ).fill()
        }
    }

    /// 去掉范围末尾的换行符 —— 算进去的话会多出一行的底色
    private func withoutTrailingNewlines(_ range: NSRange, in storage: NSTextStorage) -> NSRange {
        let units = Array(storage.string.utf16)
        var length = range.length
        while length > 0, range.location + length - 1 < units.count, units[range.location + length - 1] == 0x0A {
            length -= 1
        }
        return NSRange(location: range.location, length: length)
    }
}
