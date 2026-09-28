import AppKit

/// 界面文案的唯一起点（0.8.0「English」）。
///
/// 设计：中文是开发基准，**key 就是中文原文**——抽取是机械替换
///（`"关于 MuM"` → `L10n.t("关于 MuM")`），英文表只存「中文 → English」的映射，
/// 查不到就回退中文（并记下来，残留检查靠它）。不上 i18n 框架：
/// 一张 .strings 表 + 两级回退，就是全部机制。
///
/// 语言三态：跟随系统 / 中文 / English。系统语言非中文时落到英文
/// （一个中英双语 app，第三种语言没有界面可给）。
enum L10n {

    enum Language: Int, CaseIterable {
        case system
        case zhHans
        case english

        /// 设置面板里的选项名。语言名按惯例用自己的语言写（System 会随界面语言走）
        var title: String {
            switch self {
            case .system: return L10n.t("跟随系统")
            case .zhHans: return "中文"
            case .english: return "English"
            }
        }
    }

    /// 实际生效的语言（只有两种）
    enum Effective {
        case zhHans
        case english
    }

    /// 用户覆盖（设置项）。赋值即切换：发通知，菜单和各窗口收到后重挂文案
    static var override: Language = .system {
        didSet {
            guard override != oldValue else { return }
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
    }

    static var effective: Effective {
        switch override {
        case .zhHans: return .zhHans
        case .english: return .english
        case .system:
            let preferred = Locale.preferredLanguages.first ?? "en"
            return preferred.hasPrefix("zh") ? .zhHans : .english
        }
    }

    static let didChangeNotification = Notification.Name("MuM.languageDidChange")

    /// 查文案。key = 中文原文；英文表缺失 → 回退中文并记入 missing（残留检查用）
    static func t(_ key: String) -> String {
        guard effective == .english else { return key }
        if let translated = englishTable[key], !translated.isEmpty {
            return translated
        }
        missingKeys.insert(key)
        return key
    }

    /// 带参数的文案。格式串整体进表（`"已忽略 %@"` → `"Ignored %@"`），
    /// 不许在调用点拼句子
    static func f(_ key: String, _ args: CVarArg...) -> String {
        String(format: t(key), arguments: args)
    }

    // MARK: - 表

    /// 英文表：中文原文 → English。懒加载一次。
    private static let englishTable: [String: String] = loadEnglishTable()

    /// 查不到英文的 key 都记在这里——「EN 模式零中文残留」的自动检查读它
    private(set) static var missingKeys: Set<String> = []

    /// 诊断/自检用：当前生效语言 + 表规模 + 缺失数
    static var debugSummary: String {
        "lang=\(effective == .english ? "en" : "zh") table=\(englishTable.count) missing=\(missingKeys.count)"
    }

    /// 英文表的位置：发布包在 Contents/Resources/L10n/en.strings（build-app.sh 拷），
    /// 开发/测试从源码树读（#filePath 推仓库根，swift build 的裸二进制没有 bundle）
    private static func loadEnglishTable() -> [String: String] {
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources.appendingPathComponent("L10n/en.strings"))
        }
        // Sources/MuM/Core/L10n.swift → 上四级是仓库根（Core → MuM → Sources → 根）
        let sourceRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        candidates.append(sourceRoot.appendingPathComponent("Resources/L10n/en.strings"))

        for url in candidates {
            guard let dict = NSDictionary(contentsOf: url) as? [String: String], !dict.isEmpty else { continue }
            return dict
        }
        return [:]
    }
}
