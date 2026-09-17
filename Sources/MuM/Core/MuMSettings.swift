import AppKit

/// 用户偏好。
///
/// 集中在一处而不是散落成十几个 UserDefaults key：设置面板要成批读写，窗口控制器要
/// 成批应用到排版和编辑器上，中间隔着一个 struct 比隔着一堆 key 清楚得多。
struct MuMSettings {

    // MARK: - 系统

    /// 启动时的呈现方式。会话内用户切换模式不受它影响 ——
    /// 它只决定"刚打开时用哪种"，不是"强制锁定"。
    enum StartMode: Int, CaseIterable {
        case write
        case read
        case preview

        var title: String {
            switch self {
            case .write: return "Write"
            case .read: return "Read"
            case .preview: return "Preview"
            }
        }
    }

    /// 启动时恢复上次打开的项目和文件
    var restoresLastSession = true
    /// 启动时用哪种呈现方式
    var startMode: StartMode = .read
    /// 文件树是否显示 `.` 开头的隐藏文件
    var showsHiddenFiles = false
    /// Tab 缩进的空格数
    var indentWidth = 2

    // MARK: - 外观

    enum Appearance: Int, CaseIterable {
        case system
        case light
        case dark

        var title: String {
            switch self {
            case .system: return "跟随系统"
            case .light: return "亮色"
            case .dark: return "暗色"
            }
        }

        /// nil 表示交回系统决定 —— `NSApp.appearance` 设成 nil 就是"跟随系统"
        var nsAppearance: NSAppearance? {
            switch self {
            case .system: return nil
            case .light: return NSAppearance(named: .aqua)
            case .dark: return NSAppearance(named: .darkAqua)
            }
        }
    }

    var appearance: Appearance = .system
    /// 阅读面主题（纸色）。和应用外观正交。
    var readingTheme: ReadingTheme = .system

    // MARK: - 排版（影响预览）

    /// 正文字号
    var previewFontSize: CGFloat = 15
    /// 行距（额外的行间空白，pt）
    var lineSpacing: CGFloat = 4
    /// 段间距倍数：1.0 是设计基准，调大更松散
    var blockSpacing: CGFloat = 1.0
    /// 正文最大宽度
    var readingWidth: MarkdownTheme.ReadingWidth = .standard
    /// 正文字族
    var previewFont: PreviewFont = .system
    /// 字间距（pt）
    var letterSpacing: CGFloat = 0

    // MARK: - 编辑器

    /// 源码编辑区字号
    var editorFontSize: CGFloat = 13
    /// 是否显示行号
    var showsLineNumbers = false
    /// 是否高亮光标所在行
    var highlightsCurrentLine = true
    /// 打字机模式：让光标所在行始终停在编辑区中间
    var typewriterMode = false

    // MARK: - 取值范围

    static let previewFontSizeRange: ClosedRange<CGFloat> = 11...30
    static let editorFontSizeRange: ClosedRange<CGFloat> = 11...20
    static let lineSpacingRange: ClosedRange<CGFloat> = 0...12
    static let blockSpacingRange: ClosedRange<CGFloat> = 0.5...2.0
    static let letterSpacingRange: ClosedRange<CGFloat> = 0...2.0
}

// MARK: - 持久化

/// 读写 `MuMSettings`。整体存成一个字典，避免 key 越加越乱。
enum SettingsStore {

    private static let key = "MuM.settings"

    // 早期版本用的散装 key，首次读取时迁移过来，不丢用户已调过的值
    private static let legacyFontSizeKey = "MuM.previewFontSize"
    private static let legacyReadingWidthKey = "MuM.readingWidth"

    static func load() -> MuMSettings {
        var settings = MuMSettings()

        if let stored = UserDefaults.standard.dictionary(forKey: key) {
            if let value = boolean(stored["restoresLastSession"]) { settings.restoresLastSession = value }
            if let value = number(stored["startMode"]),
               let mode = MuMSettings.StartMode(rawValue: Int(value)) { settings.startMode = mode }
            if let value = boolean(stored["showsHiddenFiles"]) { settings.showsHiddenFiles = value }
            if let value = number(stored["indentWidth"]) { settings.indentWidth = Int(value) }
            if let value = number(stored["appearance"]),
               let appearance = MuMSettings.Appearance(rawValue: Int(value)) { settings.appearance = appearance }
            if let value = number(stored["readingTheme"]),
               let theme = ReadingTheme(rawValue: Int(value)) { settings.readingTheme = theme }
            if let value = number(stored["previewFont"]),
               let font = PreviewFont(rawValue: Int(value)) { settings.previewFont = font }
            if let value = number(stored["letterSpacing"]) { settings.letterSpacing = CGFloat(value) }
            if let value = boolean(stored["typewriterMode"]) { settings.typewriterMode = value }
            if let value = number(stored["previewFontSize"]) { settings.previewFontSize = CGFloat(value) }
            if let value = number(stored["lineSpacing"]) { settings.lineSpacing = CGFloat(value) }
            if let value = number(stored["blockSpacing"]) { settings.blockSpacing = CGFloat(value) }
            if let value = number(stored["editorFontSize"]) { settings.editorFontSize = CGFloat(value) }
            if let value = number(stored["readingWidth"]),
               let width = MarkdownTheme.ReadingWidth(rawValue: Int(value)) { settings.readingWidth = width }
            if let value = boolean(stored["showsLineNumbers"]) { settings.showsLineNumbers = value }
            if let value = boolean(stored["highlightsCurrentLine"]) { settings.highlightsCurrentLine = value }
            return settings
        }

        // 没有新格式的记录 → 尝试从旧 key 迁移
        let legacySize = UserDefaults.standard.double(forKey: legacyFontSizeKey)
        if legacySize > 0 { settings.previewFontSize = legacySize }

        let legacyWidth = UserDefaults.standard.double(forKey: legacyReadingWidthKey)
        if legacyWidth > 0, let width = MarkdownTheme.ReadingWidth(rawValue: Int(legacyWidth)) {
            settings.readingWidth = width
        }

        return settings
    }

    // MARK: - 取值
    //
    // 不直接 `as? Bool` / `as? Double`：存进去的可能是 Bool、NSNumber，
    // 也可能是字符串 —— 手写 plist 时 `defaults write` 会把裸写的 1 存成 "1"。
    // 类型对不上就静默读不到，表现为"设置改了没反应"，很难查。

    private static func boolean(_ value: Any?) -> Bool? {
        switch value {
        case let value as Bool: return value
        case let value as NSNumber: return value.boolValue
        case let value as String: return (value as NSString).boolValue
        default: return nil
        }
    }

    private static func number(_ value: Any?) -> Double? {
        switch value {
        case let value as Double: return value
        case let value as NSNumber: return value.doubleValue
        case let value as String: return Double(value)
        default: return nil
        }
    }

    static func save(_ settings: MuMSettings) {
        UserDefaults.standard.set([
            "restoresLastSession": settings.restoresLastSession,
            "startMode": settings.startMode.rawValue,
            "showsHiddenFiles": settings.showsHiddenFiles,
            "indentWidth": settings.indentWidth,
            "appearance": settings.appearance.rawValue,
            "readingTheme": settings.readingTheme.rawValue,
            "previewFont": settings.previewFont.rawValue,
            "letterSpacing": Double(settings.letterSpacing),
            "typewriterMode": settings.typewriterMode,
            "previewFontSize": Double(settings.previewFontSize),
            "lineSpacing": Double(settings.lineSpacing),
            "blockSpacing": Double(settings.blockSpacing),
            "readingWidth": settings.readingWidth.rawValue,
            "editorFontSize": Double(settings.editorFontSize),
            "showsLineNumbers": settings.showsLineNumbers,
            "highlightsCurrentLine": settings.highlightsCurrentLine,
        ], forKey: key)
    }
}
