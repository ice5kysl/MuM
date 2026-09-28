import AppKit

// 预览区用的自定义富文本属性。它们不参与绘制本身，而是在 PreviewTextView 里
// 被读出来手工画：引用块左侧的竖线、分隔线、标题下的细线。
// 这样不用引入 Web 视图就能得到接近排版软件的观感。
extension NSAttributedString.Key {
    static let mumQuoteDepth = NSAttributedString.Key("MuM.quoteDepth")
    static let mumQuoteColor = NSAttributedString.Key("MuM.quoteColor")
    static let mumHorizontalRule = NSAttributedString.Key("MuM.horizontalRule")
    static let mumHeadingRule = NSAttributedString.Key("MuM.headingRule")
    /// 代码块范围（值为底色）。底色不交给 TextKit 的 `.backgroundColor` 绘制，
    /// 而是由 PreviewLayoutManager 统一在文字下方填整块 —— 原因见那里。
    static let mumCodeBlock = NSAttributedString.Key("MuM.codeBlock")
    /// 查找命中。值 `Int`：1 = 当前这一处，0 = 其它命中。
    /// 不用 `.backgroundColor` 画 —— 行内代码的底色就是它，会打架。
    /// 改由 PreviewLayoutManager 在文字**下方**画，和代码块底色同一套机制。
    static let mumFindMatch = NSAttributedString.Key("MuM.findMatch")
}

/// 正文使用的字族
enum PreviewFont: Int, CaseIterable {
    case system
    case serif
    case monospaced

    var title: String {
        switch self {
        case .system: return L10n.t("系统")
        case .serif: return L10n.t("衬线")
        case .monospaced: return L10n.t("等宽")
        }
    }

    var design: NSFontDescriptor.SystemDesign {
        switch self {
        case .system: return .default
        case .serif: return .serif
        case .monospaced: return .monospaced
        }
    }
}

extension String {
    /// 是否含 CJK 字符（汉字 / 假名 / 谚文 / 全角标点）。
    /// 排版参数按书写系统分开调的依据：1.73 倍行高这类调校是 CJK 舒适区，
    /// 对纯拉丁段落只做加法、不改 CJK 的账（0.8.0「English」）。
    var mumContainsCJK: Bool {
        unicodeScalars.contains { scalar in
            switch scalar.value {
            case 0x3000...0x303F,   // CJK 标点
                 0x3040...0x30FF,   // 平/片假名
                 0x3400...0x4DBF,   // 扩展 A
                 0x4E00...0x9FFF,   // 基本汉字
                 0xAC00...0xD7AF,   // 谚文音节
                 0xF900...0xFAFF,   // 兼容汉字
                 0xFF00...0xFF65:   // 全角 forms
                return true
            default:
                return false
            }
        }
    }
}

/// 预览区排版与配色。
///
/// 配色全部来自 `ReadingTheme.palette` —— 这一层不再直接读语义色，这样换主题
/// 只需要换一个色板，不用在渲染器里到处判断。
struct MarkdownTheme {

    // MARK: - 用户偏好（由设置面板驱动）

    /// 正文字号
    var baseSize: CGFloat = 15
    /// 正文最大宽度，超出后居中留白 —— 长行在宽窗口里极难阅读
    var maxContentWidth: CGFloat = 780
    /// 行距：额外的行间空白（pt）
    var lineSpacing: CGFloat = 4
    /// 段间距倍数。1.0 是设计基准，调大整体更松散。
    var blockSpacingScale: CGFloat = 1.0
    /// 字间距（pt）
    var letterSpacing: CGFloat = 0

    // MARK: - 拉丁段落度量（0.8.0「English」）
    //
    // CJK 调校只作用在含 CJK 的段落上；纯拉丁段落用这一套，只做加法。
    // 实测口径（SF 15pt）：自然行盒 ≈20pt，+2pt 额外行距 ≈ 1.46 倍行高；
    // 拉丁均宽实测 6.87pt/字符，标尺宽 550pt ≈ 每行 80 个拉丁字符
    // （CJK 780pt ≈ 50 个汉字；英文舒适区 60–85）。

    /// 拉丁（无 CJK）段落的行距：跟随用户的行距旋钮按比例收，保底 2pt
    var latinLineSpacing: CGFloat { max(2, (lineSpacing * 0.3).rounded()) }
    /// 拉丁段落的字距：CJK 用户加的字距放进英文单词间会散，收六成
    var latinLetterSpacing: CGFloat { (letterSpacing * 0.4 * 2).rounded() / 2 }
    /// 纯拉丁文档的标尺宽上限（pt）
    static let latinContentWidthCap: CGFloat = 550
    /// 正文字族
    var previewFont: PreviewFont = .system
    /// 阅读主题（纸色）
    var readingTheme: ReadingTheme = .system

    /// 阅读宽度的可选档位（pt）
    enum ReadingWidth: Int, CaseIterable {
        case narrow = 660
        case standard = 780
        case wide = 920

        var title: String {
            switch self {
            case .narrow: return L10n.t("窄")
            case .standard: return L10n.t("标准")
            case .wide: return L10n.t("宽")
            }
        }
    }

    // MARK: - 字体

    private var palette: ReadingTheme.Palette { readingTheme.palette }

    /// 按字号、字重和当前字族造字体。字族靠 `fontDescriptor.withDesign` 切换，
    /// 这样系统 / 衬线 / 等宽共用同一套字号字重逻辑。
    private func font(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        let base = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = base.fontDescriptor.withDesign(previewFont.design),
              let designed = NSFont(descriptor: descriptor, size: size) else { return base }
        return designed
    }

    var bodyFont: NSFont { font(size: baseSize, weight: .regular) }
    var boldFont: NSFont { font(size: baseSize, weight: .semibold) }
    var italicFont: NSFont { Self.italicize(bodyFont) }
    var boldItalicFont: NSFont { Self.italicize(boldFont) }

    var codeFont: NSFont { .monospacedSystemFont(ofSize: baseSize - 1, weight: .regular) }
    var codeBoldFont: NSFont { .monospacedSystemFont(ofSize: baseSize - 1, weight: .semibold) }
    var codeBlockFont: NSFont { .monospacedSystemFont(ofSize: baseSize - 1.5, weight: .regular) }

    /// h1…h6
    var headingFonts: [NSFont] {
        let scale: [CGFloat] = [2.0, 1.55, 1.3, 1.12, 1.0, 0.94]
        let weights: [NSFont.Weight] = [.bold, .bold, .semibold, .semibold, .semibold, .semibold]
        return zip(scale, weights).map { font(size: (baseSize * $0).rounded(), weight: $1) }
    }

    private static func italicize(_ font: NSFont) -> NSFont {
        NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
    }

    // MARK: - 颜色（全部来自阅读主题）

    var textColor: NSColor { palette.text }
    var secondaryTextColor: NSColor { palette.secondary }
    var tertiaryTextColor: NSColor { palette.muted }
    var linkColor: NSColor { .linkColor }
    var headingColor: NSColor { palette.text }

    var codeTextColor: NSColor { palette.text }
    var codeBlockBackground: NSColor { palette.codeBackground }
    var inlineCodeBackground: NSColor { palette.inlineCodeBackground }

    var tableBorderColor: NSColor { palette.separator }
    var tableHeaderBackground: NSColor { palette.tableHeader }

    var quoteBarColor: NSColor { palette.separator }
    var quoteTextColor: NSColor { palette.secondary }
    var ruleColor: NSColor { palette.separator }

    /// <mark> 高亮底色，明暗主题下都成立
    var markBackground: NSColor { NSColor.systemYellow.withAlphaComponent(0.32) }

    /// 阅读面底色 —— PreviewViewController 也要用它设置文本视图背景
    var backgroundColor: NSColor { palette.background }

    // MARK: - 语法高亮配色
    //
    // 全部来自阅读主题的色板。**不能**直接用 `.secondaryLabelColor` 这类语义色：
    // 语义色跟着应用外观解析，而纸色由阅读主题决定 —— 暗色应用 + "纸"主题时，
    // 注释色会解析成浅灰，压在米白纸上看不清。

    var syntaxKeyword: NSColor { palette.syntaxKeyword }
    var syntaxType: NSColor { palette.syntaxType }
    var syntaxString: NSColor { palette.syntaxString }
    var syntaxComment: NSColor { palette.syntaxComment }
    var syntaxNumber: NSColor { palette.syntaxNumber }
    var syntaxFunction: NSColor { palette.syntaxFunction }
    var syntaxConstant: NSColor { palette.syntaxConstant }
    var syntaxAttribute: NSColor { palette.syntaxAttribute }

    var findMatchColor: NSColor { palette.findMatch }
    var currentFindMatchColor: NSColor { palette.currentFindMatch }
}
