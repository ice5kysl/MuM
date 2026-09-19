import AppKit

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}

/// 视觉规范集中在这里，所有面板从同一套尺寸和颜色取值。
///
/// 参考 Antigravity IDE 与 Lineform 的观感，原则是：**靠留白、圆角和「一档强调色」
/// 建立层次，而不是靠边框和阴影堆叠**。浅色面板、极淡的分隔线、选中态用染色而非
/// 实心色块 —— 后者在需要长时间注视的列表里太吵。
///
/// 颜色全部用 `NSColor(name:dynamicProvider:)` 显式定义，而不是 `blended(withFraction:)`
/// 拼出来：后者会立刻解析成静态色，切换明暗模式时不会跟着变。
enum MuMDesign {

    // MARK: - 尺寸

    static let projectsPaneWidth: CGFloat = 218
    static let projectsPaneMinWidth: CGFloat = 196
    static let projectsPaneMaxWidth: CGFloat = 300

    static let treePaneWidth: CGFloat = 250
    static let treePaneMinWidth: CGFloat = 214
    static let treePaneMaxWidth: CGFloat = 420

    /// 内容栏的最小宽度：低于这个数，并排对照就没法看了
    static let contentPaneMinWidth: CGFloat = 420

    static let paneHeaderHeight: CGFloat = 40
    static let statusBarHeight: CGFloat = 26

    /// 标题带高度的兜底值。正常应当从 `safeAreaInsets.top` 取（系统给的就是标准
    /// 标题栏高度），只有在安全区还不可用时才退回这个值。
    static let titleStripHeight: CGFloat = 28

    /// 红绿灯占掉的横向空间。
    /// 前两栏都收起时，内容栏会变成最左栏，它的文件名必须躲开这一块。
    static let trafficLightsReserve: CGFloat = 78

    /// 内容栏控件平时的左内边距
    static let contentTitleLeadingInset: CGFloat = 16

    /// 三栏并排时的最小可用内容尺寸。它会作为硬约束加在根视图上，
    /// 因为只设 NSWindow.minSize 挡不住 AppKit 按 fitting size 收缩窗口。
    static let minWindowContentWidth: CGFloat = 940
    static let minWindowContentHeight: CGFloat = 520
    static let defaultWindowContentSize = NSSize(width: 1440, height: 900)

    static let projectRowHeight: CGFloat = 56
    static let treeRowHeight: CGFloat = 26

    /// 列表左右留白，让选中高亮不贴边
    static let paneInset: CGFloat = 8
    static let cornerRadius: CGFloat = 7

    /// 内容区顶栏在标题栏安全区之下再下探的高度 —— 顶栏不只是标题栏的附属，
    /// 它承载文件名、模式开关、操作菜单，需要自己的呼吸空间
    static let titleStripExtra: CGFloat = 12

    /// 内容区文档标题的字号：加大到 16pt semibold，文件名是这一栏的主角
    static let contentTitleLarge = NSFont.systemFont(ofSize: 16, weight: .semibold)

    // MARK: - 字体

    static let paneTitle = NSFont.systemFont(ofSize: 12, weight: .semibold)
    static let rowTitle = NSFont.systemFont(ofSize: 13)
    static let rowTitleStrong = NSFont.systemFont(ofSize: 13, weight: .medium)
    static let rowSubtitle = NSFont.systemFont(ofSize: 11)
    static let badge = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .medium)
    static let status = NSFont.systemFont(ofSize: 11)
    static let contentTitle = NSFont.systemFont(ofSize: 13, weight: .semibold)

    // MARK: - 颜色

    static var accent: NSColor { .controlAccentColor }

    /// 侧栏面板底色。比内容区深一档，让白色内容浮起来
    static let paneBackground = NSColor(name: "MuM.paneBackground") { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 0.090, green: 0.094, blue: 0.110, alpha: 1) // #171820
            : NSColor(srgbRed: 0.969, green: 0.973, blue: 0.980, alpha: 1) // #F7F8FA
    }

    static let statusBarBackground = NSColor(name: "MuM.statusBarBackground") { appearance in
        appearance.isDark
            ? NSColor(srgbRed: 0.075, green: 0.078, blue: 0.094, alpha: 1)
            : NSColor(srgbRed: 0.953, green: 0.957, blue: 0.965, alpha: 1)
    }

    static let separator = NSColor(name: "MuM.separator") { appearance in
        NSColor.separatorColor.withAlphaComponent(appearance.isDark ? 0.5 : 0.65)
    }

    /// 选中行用染色高亮而不是原生实心蓝底 —— 更轻，也不会把文字颜色打反
    static let selectionFill = NSColor(name: "MuM.selectionFill") { appearance in
        NSColor.controlAccentColor.withAlphaComponent(appearance.isDark ? 0.30 : 0.16)
    }

    static let hoverFill = NSColor(name: "MuM.hoverFill") { appearance in
        appearance.isDark
            ? NSColor(white: 1, alpha: 0.07)
            : NSColor(white: 0, alpha: 0.045)
    }

    /// 项目卡片的静止底色
    static let cardFill = NSColor(name: "MuM.cardFill") { appearance in
        appearance.isDark
            ? NSColor(white: 1, alpha: 0.045)
            : NSColor(white: 0, alpha: 0.032)
    }

    static var primaryText: NSColor { .labelColor }
    static var secondaryText: NSColor { .secondaryLabelColor }
    static var tertiaryText: NSColor { .tertiaryLabelColor }
}

/// 面板底色层。跟随明暗模式自动重绘，省得每个面板控制器都写一遍外观回调。
final class PaneBackgroundView: NSView {
    private let fill: NSColor

    init(color: NSColor) {
        self.fill = color
        super.init(frame: .zero)
        wantsLayer = true
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 用 `updateLayer()` 而不是自己存一份解析好的 CGColor、再靠
    /// `viewDidChangeEffectiveAppearance` 重刷。后者要求每个视图都稳稳收到回调，
    /// 实测在未上窗口 / 离屏的场景下会漏掉个别视图，出现"同一个界面一半深一半浅"。
    /// `updateLayer()` 每次显示都用当前外观重新解析动态颜色，不依赖任何手动跟踪。
    override var wantsUpdateLayer: Bool { true }

    override func updateLayer() {
        layer?.backgroundColor = fill.cgColor
    }
}
