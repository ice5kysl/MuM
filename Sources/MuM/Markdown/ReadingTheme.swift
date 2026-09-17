import AppKit


/// 阅读主题：只决定**阅读面**长什么样 —— 纸色、文字色、代码块底色。
///
/// 刻意和应用外观分开。外观（跟随系统 / 亮色 / 暗色）管的是整个窗口：侧栏、状态栏、
/// 编辑器；阅读主题管的是"这一页纸"。两者正交，所以「亮色界面 + 暖色纸阅读」或者
/// 「暗色界面 + 高对比阅读」都成立。
enum ReadingTheme: Int, CaseIterable {
    case system
    case paper
    case quiet
    case contrast

    var title: String {
        switch self {
        case .system: return "跟随外观"
        case .paper: return "纸"
        case .quiet: return "静"
        case .contrast: return "高对比"
        }
    }

    /// 阅读面的全部颜色。渲染器只认这一组，不再直接读语义色。
    struct Palette {
        let background: NSColor
        let text: NSColor
        let secondary: NSColor
        let muted: NSColor
        let codeBackground: NSColor
        let inlineCodeBackground: NSColor
        let tableHeader: NSColor
        let separator: NSColor

        // 语法高亮色也归主题管。它们**不能**用语义色（`.secondaryLabelColor` 之类）——
        // 语义色跟着应用外观解析，而纸色是主题决定的：暗色应用 + "纸"主题时，
        // 注释色会解析成浅灰，压在米白纸上看不见。
        let syntaxKeyword: NSColor
        let syntaxType: NSColor
        let syntaxString: NSColor
        let syntaxComment: NSColor
        let syntaxNumber: NSColor
        let syntaxFunction: NSColor
        let syntaxConstant: NSColor
        let syntaxAttribute: NSColor

        // 查找命中色也归主题管。理由和语法色一样：语义色跟着应用外观解析，
        // 而纸色由阅读主题决定 —— 暗色纸面上用 systemYellow 加透明度会变成一坨闷橄榄色。
        let findMatch: NSColor
        let currentFindMatch: NSColor
    }

    var palette: Palette {
        switch self {
        case .system: return .system
        case .paper: return .paper
        case .quiet: return .quiet
        case .contrast: return .contrast
        }
    }

    /// 给设置面板画预览卡片用：背景 + 文字色
    var swatch: (background: NSColor, text: NSColor) {
        (palette.background, palette.text)
    }
}

// MARK: - 各主题的色板

extension ReadingTheme.Palette {

    /// 跟随外观：全部用语义色，明暗模式自动切换
    static var system: ReadingTheme.Palette {
        .init(
            background: .textBackgroundColor,
            text: .labelColor,
            secondary: .secondaryLabelColor,
            muted: .tertiaryLabelColor,
            codeBackground: NSColor(name: "MuM.codeBlockBackground") { appearance in
                appearance.isDark
                    ? NSColor(srgbRed: 0.145, green: 0.149, blue: 0.165, alpha: 1)
                    : NSColor(srgbRed: 0.957, green: 0.961, blue: 0.969, alpha: 1)
            },
            inlineCodeBackground: NSColor(name: "MuM.inlineCodeBackground") { appearance in
                appearance.isDark
                    ? NSColor(srgbRed: 0.204, green: 0.208, blue: 0.227, alpha: 1)
                    : NSColor(srgbRed: 0.933, green: 0.937, blue: 0.949, alpha: 1)
            },
            tableHeader: NSColor(name: "MuM.tableHeaderBackground") { appearance in
                appearance.isDark
                    ? NSColor(srgbRed: 0.176, green: 0.180, blue: 0.196, alpha: 1)
                    : NSColor(srgbRed: 0.945, green: 0.949, blue: 0.957, alpha: 1)
            },
            separator: .separatorColor
,
            syntaxKeyword: .systemPink,
            syntaxType: .systemTeal,
            syntaxString: .systemRed,
            syntaxComment: .secondaryLabelColor,
            syntaxNumber: .systemPurple,
            syntaxFunction: .systemBlue,
            syntaxConstant: .systemOrange,
            syntaxAttribute: .systemIndigo
,
            findMatch: NSColor(name: "MuM.findMatch") { $0.isDark
                ? NSColor(srgbRed: 1.00, green: 0.86, blue: 0.35, alpha: 0.42)
                : NSColor(srgbRed: 1.00, green: 0.88, blue: 0.30, alpha: 0.55) },
            currentFindMatch: NSColor(name: "MuM.currentFindMatch") { $0.isDark
                ? NSColor(srgbRed: 1.00, green: 0.62, blue: 0.20, alpha: 0.62)
                : NSColor(srgbRed: 1.00, green: 0.58, blue: 0.10, alpha: 0.62) }
        )
    }

    /// 纸：暖白底 + 暖褐字。长时间阅读比纯白柔和，也不像纯米黄那样发黄。
    static var paper: ReadingTheme.Palette {
        .init(
            background: NSColor(srgbRed: 0.980, green: 0.965, blue: 0.937, alpha: 1), // #FAF6EF
            text: NSColor(srgbRed: 0.224, green: 0.204, blue: 0.173, alpha: 1),       // #39342C
            secondary: NSColor(srgbRed: 0.420, green: 0.388, blue: 0.337, alpha: 1),
            muted: NSColor(srgbRed: 0.549, green: 0.514, blue: 0.455, alpha: 1),
            codeBackground: NSColor(srgbRed: 0.945, green: 0.925, blue: 0.882, alpha: 1),
            inlineCodeBackground: NSColor(srgbRed: 0.929, green: 0.906, blue: 0.855, alpha: 1),
            tableHeader: NSColor(srgbRed: 0.949, green: 0.929, blue: 0.886, alpha: 1),
            separator: NSColor(srgbRed: 0.847, green: 0.816, blue: 0.753, alpha: 1)
,
            syntaxKeyword: NSColor(srgbRed: 0.651, green: 0.149, blue: 0.643, alpha: 1), // #A626A4
            syntaxType: NSColor(srgbRed: 0.757, green: 0.518, blue: 0.004, alpha: 1),    // #C18401
            syntaxString: NSColor(srgbRed: 0.314, green: 0.631, blue: 0.310, alpha: 1),  // #50A14F
            syntaxComment: NSColor(srgbRed: 0.545, green: 0.529, blue: 0.494, alpha: 1), // #8B8780
            syntaxNumber: NSColor(srgbRed: 0.596, green: 0.408, blue: 0.004, alpha: 1),  // #986801
            syntaxFunction: NSColor(srgbRed: 0.251, green: 0.471, blue: 0.949, alpha: 1),// #4078F2
            syntaxConstant: NSColor(srgbRed: 0.596, green: 0.408, blue: 0.004, alpha: 1),
            syntaxAttribute: NSColor(srgbRed: 0.757, green: 0.518, blue: 0.004, alpha: 1)
,
            findMatch: NSColor(srgbRed: 1.00, green: 0.88, blue: 0.30, alpha: 0.55),
            currentFindMatch: NSColor(srgbRed: 1.00, green: 0.58, blue: 0.10, alpha: 0.62)
        )
    }

    /// 静：固定的暗色阅读面。即使应用是亮色，读长文也可以只让"这一页"暗下来。
    static var quiet: ReadingTheme.Palette {
        .init(
            background: NSColor(srgbRed: 0.106, green: 0.106, blue: 0.118, alpha: 1), // #1B1B1E
            text: NSColor(srgbRed: 0.902, green: 0.902, blue: 0.914, alpha: 1),       // #E6E6E9
            secondary: NSColor(srgbRed: 0.694, green: 0.694, blue: 0.718, alpha: 1),
            muted: NSColor(srgbRed: 0.518, green: 0.518, blue: 0.545, alpha: 1),
            codeBackground: NSColor(srgbRed: 0.161, green: 0.161, blue: 0.180, alpha: 1),
            inlineCodeBackground: NSColor(srgbRed: 0.204, green: 0.204, blue: 0.227, alpha: 1),
            tableHeader: NSColor(srgbRed: 0.180, green: 0.180, blue: 0.200, alpha: 1),
            separator: NSColor(srgbRed: 0.286, green: 0.286, blue: 0.310, alpha: 1)
,
            syntaxKeyword: NSColor(srgbRed: 0.776, green: 0.471, blue: 0.867, alpha: 1), // #C678DD
            syntaxType: NSColor(srgbRed: 0.898, green: 0.753, blue: 0.482, alpha: 1),    // #E5C07B
            syntaxString: NSColor(srgbRed: 0.596, green: 0.765, blue: 0.475, alpha: 1),  // #98C379
            syntaxComment: NSColor(srgbRed: 0.545, green: 0.576, blue: 0.612, alpha: 1), // #8B939C
            syntaxNumber: NSColor(srgbRed: 0.820, green: 0.604, blue: 0.400, alpha: 1),  // #D19A66
            syntaxFunction: NSColor(srgbRed: 0.380, green: 0.686, blue: 0.937, alpha: 1),// #61AFEF
            syntaxConstant: NSColor(srgbRed: 0.820, green: 0.604, blue: 0.400, alpha: 1),
            syntaxAttribute: NSColor(srgbRed: 0.337, green: 0.714, blue: 0.761, alpha: 1)
,
            findMatch: NSColor(srgbRed: 1.00, green: 0.86, blue: 0.35, alpha: 0.42),
            currentFindMatch: NSColor(srgbRed: 1.00, green: 0.62, blue: 0.20, alpha: 0.62)
        )
    }

    /// 高对比：纯白纯黑，给需要最大清晰度的场合（投屏、视力吃紧）
    static var contrast: ReadingTheme.Palette {
        .init(
            background: .white,
            text: .black,
            secondary: NSColor(srgbRed: 0.180, green: 0.180, blue: 0.180, alpha: 1),
            muted: NSColor(srgbRed: 0.350, green: 0.350, blue: 0.350, alpha: 1),
            codeBackground: NSColor(srgbRed: 0.937, green: 0.937, blue: 0.937, alpha: 1),
            inlineCodeBackground: NSColor(srgbRed: 0.910, green: 0.910, blue: 0.910, alpha: 1),
            tableHeader: NSColor(srgbRed: 0.925, green: 0.925, blue: 0.925, alpha: 1),
            separator: NSColor(srgbRed: 0.400, green: 0.400, blue: 0.400, alpha: 1)
,
            syntaxKeyword: NSColor(srgbRed: 0.478, green: 0.122, blue: 0.635, alpha: 1), // #7A1FA2
            syntaxType: NSColor(srgbRed: 0.541, green: 0.353, blue: 0.000, alpha: 1),    // #8A5A00
            syntaxString: NSColor(srgbRed: 0.102, green: 0.420, blue: 0.102, alpha: 1),  // #1A6B1A
            syntaxComment: NSColor(srgbRed: 0.353, green: 0.353, blue: 0.353, alpha: 1), // #5A5A5A
            syntaxNumber: NSColor(srgbRed: 0.478, green: 0.290, blue: 0.000, alpha: 1),  // #7A4A00
            syntaxFunction: NSColor(srgbRed: 0.043, green: 0.310, blue: 0.749, alpha: 1),// #0B4FBF
            syntaxConstant: NSColor(srgbRed: 0.541, green: 0.227, blue: 0.000, alpha: 1),
            syntaxAttribute: NSColor(srgbRed: 0.416, green: 0.122, blue: 0.635, alpha: 1)
,
            findMatch: NSColor(srgbRed: 1.00, green: 0.90, blue: 0.20, alpha: 0.75),
            currentFindMatch: NSColor(srgbRed: 1.00, green: 0.55, blue: 0.00, alpha: 0.75)
        )
    }
}
