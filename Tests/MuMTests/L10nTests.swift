import XCTest
@testable import MuM

/// L10n 机制（0.8.0「English」）：语言三态解析、英文表查找、中文回退、
/// 设置持久化、英文表的形状约束。
final class L10nTests: XCTestCase {

    override func setUp() {
        super.setUp()
        L10n.override = .system
    }

    override func tearDown() {
        L10n.override = .system
        super.tearDown()
    }

    func testOverrideZhHansAlwaysChinese() {
        L10n.override = .zhHans
        XCTAssertEqual(L10n.effective, .zhHans)
        XCTAssertEqual(L10n.t("关于 MuM"), "关于 MuM", "中文模式下原样返回，不查表")
    }

    func testOverrideEnglishTranslates() {
        L10n.override = .english
        XCTAssertEqual(L10n.effective, .english)
        XCTAssertEqual(L10n.t("关于 MuM"), "About MuM")
        XCTAssertEqual(L10n.t("退出 MuM"), "Quit MuM")
    }

    func testEnglishFallsBackToChineseForMissingKey() {
        L10n.override = .english
        let missing = "一条不存在的文案"
        XCTAssertEqual(L10n.t(missing), missing, "英文表没有就回退中文")
        XCTAssertTrue(L10n.missingKeys.contains(missing), "缺失要记进 missingKeys（残留检查读它）")
    }

    func testFormatGoesThroughTable() {
        L10n.override = .zhHans
        XCTAssertEqual(L10n.f("已忽略 %@", "v1"), "已忽略 v1")
    }

    func testSystemFollowsPreferredLanguage() {
        L10n.override = .system
        // 测试进程的 preferredLanguages 由运行环境决定，不断言具体值，
        // 只断言解析规则自洽：非中文环境 → english，中文环境 → zhHans
        let preferred = Locale.preferredLanguages.first ?? "en"
        let expected: L10n.Effective = preferred.hasPrefix("zh") ? .zhHans : .english
        XCTAssertEqual(L10n.effective, expected)
    }

    func testLanguagePersistsThroughSettingsStore() {
        var settings = MuMSettings()
        settings.language = .english
        SettingsStore.save(settings)
        defer {
            var restore = MuMSettings()
            restore.language = .system
            SettingsStore.save(restore)
        }
        XCTAssertEqual(SettingsStore.load().language, .english)
    }

    func testEnglishTableCoversMenuBaseline() {
        // 菜单是第一条垂直切片：这批 key 必须在表里，缺一个 = EN 菜单混中文
        L10n.override = .english
        let menuKeys = ["文件", "编辑", "项目", "显示", "窗口", "帮助",
                        "新建文件", "保存", "导出…", "撤销", "重做",
                        "项目列表", "目录树", "大纲栏", "进入全屏幕",
                        "检查更新…", "反馈问题或建议…"]
        for key in menuKeys {
            XCTAssertNotEqual(L10n.t(key), key, "菜单文案「\(key)」没有英文")
        }
    }
}

extension L10nTests {
    /// 菜单栏即时重建（0.8.0 验收 #4）：AppDelegate.languageDidChange 走一遍，
    /// 整栏菜单标题从中文换英文、再换回来 —— 不许「半中半英」
    func testMenuRebuildsOnLanguageChange() {
        _ = NSApplication.shared // 测试进程默认没有 NSApp，MainMenuBuilder 要用
        let delegate = AppDelegate()
        L10n.override = .zhHans
        delegate.languageDidChange()
        XCTAssertEqual(NSApp.mainMenu?.item(at: 1)?.title, "文件")

        L10n.override = .english
        delegate.languageDidChange()
        XCTAssertEqual(NSApp.mainMenu?.item(at: 1)?.title, "File")
        XCTAssertEqual(NSApp.mainMenu?.item(at: 2)?.title, "Edit")

        L10n.override = .zhHans
        delegate.languageDidChange()
        XCTAssertEqual(NSApp.mainMenu?.item(at: 1)?.title, "文件")
    }
}
