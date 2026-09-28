import XCTest
import AppKit
@testable import MuM

/// 拉丁段落度量（0.8.0「English」）：纯拉丁段落换用拉丁行距/字距/标尺宽，
/// CJK 段落一个属性都不许动（中文零回归是验收红线）。
final class LatinMetricsTests: XCTestCase {

    private func render(_ markdown: String, lineSpacing: CGFloat = 7) -> (NSAttributedString, MarkdownTheme) {
        var theme = MarkdownTheme()
        theme.lineSpacing = lineSpacing
        let rendered = MarkdownRenderer(theme: theme, baseURL: nil).render(markdown)
        return (rendered, theme)
    }

    private func paragraphStyle(of text: NSAttributedString, containing needle: String) -> NSParagraphStyle? {
        let range = (text.string as NSString).range(of: needle)
        guard range.location != NSNotFound else { return nil }
        return text.attribute(.paragraphStyle, at: range.location, effectiveRange: nil) as? NSParagraphStyle
    }

    // MARK: - CJK 判定

    func testCJKDetection() {
        XCTAssertTrue("你好".mumContainsCJK)
        XCTAssertTrue("全角，标点".mumContainsCJK)
        XCTAssertTrue("ひらがな".mumContainsCJK)
        XCTAssertTrue("한국어".mumContainsCJK)
        XCTAssertTrue("mixed 混合 text".mumContainsCJK)
        XCTAssertFalse("plain english text".mumContainsCJK)
        XCTAssertFalse("numbers 123 & symbols!".mumContainsCJK)
        XCTAssertFalse("… halfwidth ellipsis".mumContainsCJK)
    }

    // MARK: - 行距

    func testLatinParagraphGetsLatinLineSpacing() {
        let (text, theme) = render("An English paragraph without any CJK at all.")
        let style = paragraphStyle(of: text, containing: "English paragraph")
        XCTAssertEqual(style?.lineSpacing, theme.latinLineSpacing)
        XCTAssertNotEqual(style?.lineSpacing, theme.lineSpacing)
    }

    func testCJKParagraphKeepsGlobalLineSpacing() {
        let (text, theme) = render("这是一段纯正的中文，行距必须一个点都不许动。")
        let style = paragraphStyle(of: text, containing: "纯正的中文")
        XCTAssertEqual(style?.lineSpacing, theme.lineSpacing, "CJK 段落保持全局行距（零回归红线）")
    }

    func testMixedParagraphKeepsGlobalLineSpacing() {
        let (text, theme) = render("中英 mixed 混排的段落按 CJK 算。")
        let style = paragraphStyle(of: text, containing: "mixed")
        XCTAssertEqual(style?.lineSpacing, theme.lineSpacing, "含一个 CJK 字符就按 CJK 待遇")
    }

    func testCodeBlockKeepsItsOwnLineSpacing() {
        let (text, _) = render("```swift\nlet a = 1\nlet b = 2\n```")
        let style = paragraphStyle(of: text, containing: "let a")
        XCTAssertEqual(style?.lineSpacing, 4, "代码块的紧凑行距不许被拉丁化")
    }

    func testLatinLineSpacingFollowsUserKnob() {
        var theme = MarkdownTheme()
        theme.lineSpacing = 7
        XCTAssertEqual(theme.latinLineSpacing, 2, "7pt CJK 行距 → 拉丁收 ≈2pt（≈1.46 倍行高）")
        theme.lineSpacing = 12
        XCTAssertEqual(theme.latinLineSpacing, 4, "用户调大，拉丁按比例跟")
        theme.lineSpacing = 0
        XCTAssertEqual(theme.latinLetterSpacing, 0)
    }

    // MARK: - 字距

    func testLatinParagraphGetsReducedKern() {
        var theme = MarkdownTheme()
        theme.lineSpacing = 7
        theme.letterSpacing = 1.5
        let text = MarkdownRenderer(theme: theme, baseURL: nil).render("An English paragraph.")
        let range = (text.string as NSString).range(of: "English")
        let kern = text.attribute(.kern, at: range.location, effectiveRange: nil) as? CGFloat
        XCTAssertEqual(kern, theme.latinLetterSpacing)
        XCTAssertEqual(theme.latinLetterSpacing, 0.5, "1.5pt CJK 字距 → 拉丁收六成到 0.5")
    }

    // MARK: - 标尺宽

    func testLatinWidthCapIsTypographicallySane() {
        // 记数：SF 15pt 下拉丁均宽实测，550pt 每行字符数应落在 65–85 的舒适区
        let font = NSFont.systemFont(ofSize: 15)
        let sample = String(repeating: "the quick brown fox jumps over a lazy dog. ", count: 10)
        let advance = (sample as NSString).size(withAttributes: [.font: font]).width / CGFloat(sample.count)
        let charsPerLine = MarkdownTheme.latinContentWidthCap / advance
        print("[latin-metrics] SF 15pt 拉丁均宽 \(String(format: "%.2f", advance))pt，" +
              "\(Int(MarkdownTheme.latinContentWidthCap))pt ≈ \(String(format: "%.0f", charsPerLine)) 字符/行")
        XCTAssertGreaterThan(charsPerLine, 65)
        XCTAssertLessThan(charsPerLine, 85)
    }
}
