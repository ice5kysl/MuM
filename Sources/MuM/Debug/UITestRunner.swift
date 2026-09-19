import AppKit

/// 应用内自驱动 UI 测试：`MuM --uitest <场景|all> [文档.md]`。
///
/// 为什么存在：外部模拟点击（Accessibility / AppleScript / CGEvent）要权限且不可靠。
/// 这里反过来 —— 让应用自己程序化触发自己的动作（状态栏按钮、设置面板控件、
/// 查找、大纲、全局搜索），每步之后断言状态。零权限、可复现、能进 CI。
///
/// 与 --snapshot 的区别：不用固定时长的 runloop 睡眠。每步轮询状态直到条件满足
/// 或超时，超时算失败 —— CI 机器再慢也只是多等一会儿，不会假性通过。
///
/// 环境隔离：CLI 二进制的 UserDefaults 域是进程名（MuM），与 .app（ai.jiker.mum）
/// 不共享；即便如此，跑之前仍快照并清空 MuM.* 键，跑完还原 —— 结果可复现，
/// 不受上一次测试残留的偏好影响，也不污染同域名的其他调试工具。
///
/// 退出码：0 = 全绿，1 = 有失败，2 = 用法错误。
enum UITestRunner {

    /// 场景名（也是命令行参数）与中文名
    private static let allScenarios: [(name: String, title: String)] = [
        ("settings", "设置面板"),
        ("popovers", "设置 popover"),
        ("mode", "模式切换"),
        ("find", "文档内查找"),
        ("outline", "大纲"),
        ("search", "全局搜索"),
        ("export", "导出（⌘⇧E）"),
    ]

    static func run(arguments: [String]) -> Int32 {
        guard let flagIndex = arguments.firstIndex(of: "--uitest"),
              flagIndex + 1 < arguments.count else {
            return usage()
        }
        let scenarioArg = arguments[flagIndex + 1]
        let names: [String]
        if scenarioArg == "all" {
            names = allScenarios.map(\.name)
        } else if allScenarios.contains(where: { $0.name == scenarioArg }) {
            names = [scenarioArg]
        } else {
            FileHandle.standardError.write("未知场景：\(scenarioArg)\n".data(using: .utf8)!)
            return usage()
        }

        // 文档参数可省：默认用仓库里的 demo 文档（含多级标题、可搜索词）
        let docPath = flagIndex + 2 < arguments.count
            ? arguments[flagIndex + 2]
            : FileManager.default.currentDirectoryPath + "/Examples/demo/README.md"
        let docURL = URL(fileURLWithPath: docPath).standardizedFileURL
        guard let sourceText = try? String(contentsOf: docURL, encoding: .utf8) else {
            FileHandle.standardError.write(
                "读不到文档：\(docPath)（可显式传入：MuM --uitest \(scenarioArg) <文档.md>）\n".data(using: .utf8)!)
            return 2
        }

        // 偏好隔离：快照 → 清空 → 跑 → 还原（defer 兜底，任何退出路径都还原）
        let defaults = UserDefaults.standard
        let saved = defaults.dictionaryRepresentation().filter { $0.key.hasPrefix("MuM.") }
        for key in saved.keys { defaults.removeObject(forKey: key) }
        defer {
            for key in defaults.dictionaryRepresentation().keys where key.hasPrefix("MuM.") {
                defaults.removeObject(forKey: key)
            }
            for (key, value) in saved { defaults.set(value, forKey: key) }
        }

        // AppKit 视图体系需要 NSApplication 存在，但不需要 run()（同 SnapshotRenderer）。
        // accessory：窗口不上屏、不抢焦点、不进 Dock —— 用户屏幕上可能正开着真实的 MuM
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        // 钉住外观：没有真实窗口时语义色可能解析跑偏（同 SnapshotRenderer）
        app.appearance = NSAppearance(named: .aqua)

        let controller = MainWindowController()
        guard let window = controller.window else {
            FileHandle.standardError.write("无法建立窗口\n".data(using: .utf8)!)
            return 1
        }
        window.setContentSize(MuMDesign.defaultWindowContentSize)
        // popover 只在"可见窗口"里才弹得出 —— 离屏窗口 show() 会静默失败（isShown 恒 false）。
        // 解法：把窗口挪到所有屏幕之外再 orderFrontRegardless。对窗口系统它是"可见"的，
        // popover 能正常弹出；用户屏幕上什么都看不到，accessory 不激活也不抢焦点
        // （orderFrontRegardless 是 ScrollBench 已验证过的先例，这里再加一道屏外保险）。
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()
        // 首次布局跑完再开始（面板宽度和分隔线位置都在这一步定下来）—— 轮询而非睡死
        guard wait(5, { window.contentView?.bounds.width ?? 0 >= MuMDesign.minWindowContentWidth }) else {
            FileHandle.standardError.write("窗口未能完成初始布局\n".data(using: .utf8)!)
            return 1
        }

        print("文档  \(docURL.path)")
        print("场景  \(names.joined(separator: ", "))")
        print("")

        var checkers: [Checker] = []
        for name in names {
            let title = allScenarios.first(where: { $0.name == name })?.title ?? name
            print("■ \(name)（\(title)）")
            let check = Checker(name: name)
            switch name {
            case "settings": scenarioSettings(controller, check)
            case "popovers": scenarioPopovers(controller, check)
            case "mode": scenarioMode(controller, docURL, sourceText, check)
            case "find": scenarioFind(controller, docURL, check)
            case "outline": scenarioOutline(controller, docURL, check)
            case "search": scenarioSearch(controller, docURL, check)
            case "export": scenarioExport(controller, docURL, check)
            default: break
            }
            checkers.append(check)
            print("")
        }

        // 通过 / 失败清单：失败要能看到"第几步、期望什么、实际什么"
        print("—— 清单 ——")
        var failedSteps = 0
        for check in checkers {
            let passed = check.steps.filter(\.ok).count
            failedSteps += check.steps.count - passed
            print("\(passed == check.steps.count ? "✅" : "❌") \(check.name)  \(passed)/\(check.steps.count)")
            for step in check.steps where !step.ok {
                print("   第 \(step.index) 步 \(step.name)：期望 \(step.expected)，实际 \(step.actual)")
            }
        }
        if failedSteps == 0 {
            print("总计 \(checkers.count) 个场景全绿")
            return 0
        }
        print("总计 \(checkers.count) 个场景，\(failedSteps) 步失败")
        return 1
    }

    private static func usage() -> Int32 {
        let names = (["all"] + allScenarios.map(\.name)).joined(separator: "|")
        FileHandle.standardError.write("用法：MuM --uitest <\(names)> [文档.md]\n".data(using: .utf8)!)
        return 2
    }

    // MARK: - 场景一：设置面板
    //
    // 每个滑块 / 分段 / 开关都设一个非默认值，断言两件事：MuMSettings 变了
    // （面板 → 窗口控制器的链路通），控件读回一致（界面没有和实际值脱节）。
    // 最后「恢复默认」再断言一遍 —— 回写路径和正向路径一样容易出映射错位。

    private static func scenarioSettings(_ c: MainWindowController, _ check: Checker) {
        c.debugShowDisplaySettings()
        guard check.waitFor("弹出显示设置面板", expected: "popover 显示且内容为设置面板",
                            condition: { c.debugDisplaySettingsShown && c.debugDisplaySettingsPanel != nil },
                            actual: { "isShown=\(c.debugDisplaySettingsShown)" }),
              let panel = c.debugDisplaySettingsPanel else { return }

        checkSlider(panel.debugSlider("previewFontSize"), key: "previewFontSize", value: 22,
                    in: c, check, setting: \.previewFontSize)
        checkSlider(panel.debugSlider("lineSpacing"), key: "lineSpacing", value: 12,
                    in: c, check, setting: \.lineSpacing)
        checkSlider(panel.debugSlider("blockSpacing"), key: "blockSpacing", value: 1.5,
                    in: c, check, setting: \.blockSpacing)
        checkSlider(panel.debugSlider("letterSpacing"), key: "letterSpacing", value: 1.0,
                    in: c, check, setting: \.letterSpacing)
        checkSlider(panel.debugSlider("editorFontSize"), key: "editorFontSize", value: 18,
                    in: c, check, setting: \.editorFontSize)
        // "设置变了"和"编辑区跟上"是两件事 —— applySettings 的落地也要断言
        check.expect(c.debugEditor.debugAppliedFontSize == 18,
                     "编辑区字号跟随设置", expected: "18",
                     actual: "\(format(c.debugEditor.debugAppliedFontSize))")

        checkSegment(panel.debugSegment("appearance"), key: "appearance", index: 2,
                     expected: MuMSettings.Appearance.dark, in: c, check, setting: \.appearance)
        checkSegment(panel.debugSegment("previewFont"), key: "previewFont", index: 1,
                     expected: PreviewFont.serif, in: c, check, setting: \.previewFont)
        checkSegment(panel.debugSegment("readingWidth"), key: "readingWidth", index: 2,
                     expected: MarkdownTheme.ReadingWidth.wide, in: c, check, setting: \.readingWidth)

        // 阅读主题不是标准控件，走主题卡片的 onClick 路径
        panel.debugClickTheme(.paper)
        check.expect(c.debugSettings.readingTheme == .paper,
                     "主题卡片 → paper", expected: "paper",
                     actual: "\(c.debugSettings.readingTheme)")

        checkToggle(panel.debugToggle("showsLineNumbers"), key: "showsLineNumbers", want: true,
                    in: c, check, setting: \.showsLineNumbers)
        check.expect(c.debugEditor.debugLineNumbersVisible,
                     "行号出现在编辑区", expected: "rulersVisible", actual: "未显示")
        checkToggle(panel.debugToggle("highlightsCurrentLine"), key: "highlightsCurrentLine", want: false,
                    in: c, check, setting: \.highlightsCurrentLine)
        check.expect(!c.debugEditor.debugCurrentLineHighlightOn,
                     "编辑区当前行高亮关闭", expected: "off", actual: "仍开着")
        checkToggle(panel.debugToggle("typewriterMode"), key: "typewriterMode", want: true,
                    in: c, check, setting: \.typewriterMode)

        // 恢复默认：正向改一遍之后再回写一遍，两条路径都要对
        panel.debugReset()
        let d = MuMSettings()
        let s = c.debugSettings
        check.expect(
            s.previewFontSize == d.previewFontSize && s.lineSpacing == d.lineSpacing
                && s.blockSpacing == d.blockSpacing && s.letterSpacing == d.letterSpacing
                && s.editorFontSize == d.editorFontSize && s.appearance == d.appearance
                && s.previewFont == d.previewFont && s.readingWidth == d.readingWidth
                && s.readingTheme == d.readingTheme && !s.showsLineNumbers
                && s.highlightsCurrentLine && !s.typewriterMode,
            "恢复默认后设置回到出厂值", expected: "全部默认", actual: c.debugSettingsDescription)
        check.expect(
            panel.debugSlider("previewFontSize")?.slider.doubleValue == Double(d.previewFontSize)
                && panel.debugToggle("typewriterMode")?.button.state == .off
                && panel.debugSegment("appearance")?.control.selectedSegment == 0,
            "恢复默认后控件读回一致", expected: "控件显示默认值",
            actual: "字号滑块=\(format(panel.debugSlider("previewFontSize")?.slider.doubleValue ?? -1))")

        // 系统设置面板（齿轮）：启动 / 文件 / 缩进
        c.debugShowSystemSettings()
        guard check.waitFor("弹出系统设置面板", expected: "popover 显示且内容为系统设置面板",
                            condition: { c.debugSystemSettingsShown && c.debugSystemSettingsPanel != nil },
                            actual: { "isShown=\(c.debugSystemSettingsShown)" }),
              let system = c.debugSystemSettingsPanel else { return }

        checkToggle(system.debugToggle("restoresLastSession"), key: "restoresLastSession", want: false,
                    in: c, check, setting: \.restoresLastSession)
        checkSegment(system.debugSegment("startMode"), key: "startMode", index: 2,
                     expected: MuMSettings.StartMode.preview, in: c, check, setting: \.startMode)
        checkToggle(system.debugToggle("showsHiddenFiles"), key: "showsHiddenFiles", want: true,
                    in: c, check, setting: \.showsHiddenFiles)
        // Tab 缩进是 index → 数值的映射（0→2，1→4），不是枚举 rawValue —— 最易写反的一处
        checkSegment(system.debugSegment("indentWidth"), key: "indentWidth", index: 1,
                     expected: 4, in: c, check, setting: \.indentWidth)

        c.debugClosePopovers()
    }

    // MARK: - 场景二：两个 popover
    //
    // 从真实的状态栏按钮触发，断言能弹出、内容对、再点一次收起 ——
    // "点按钮没反应"和"收不起来"都是真实发生过的回归形态。

    private static func scenarioPopovers(_ c: MainWindowController, _ check: Checker) {
        c.debugClosePopovers()
        _ = wait(2) { !c.debugDisplaySettingsShown && !c.debugSystemSettingsShown }

        c.debugShowDisplaySettings()
        check.waitFor("Aa → 显示设置弹出", expected: "isShown 且内容为 SettingsPanelViewController",
                      condition: { c.debugDisplaySettingsShown && c.debugDisplaySettingsPanel != nil },
                      actual: { "isShown=\(c.debugDisplaySettingsShown)" })
        c.debugShowDisplaySettings()
        check.waitFor("再点 Aa → 收起", expected: "popover 关闭",
                      condition: { !c.debugDisplaySettingsShown },
                      actual: { "仍在显示" })

        c.debugShowSystemSettings()
        check.waitFor("齿轮 → 系统设置弹出", expected: "isShown 且内容为 SystemSettingsPanelViewController",
                      condition: { c.debugSystemSettingsShown && c.debugSystemSettingsPanel != nil },
                      actual: { "isShown=\(c.debugSystemSettingsShown)" })
        c.debugClosePopovers()
        check.waitFor("关闭后两个 popover 都不显示", expected: "都关闭",
                      condition: { !c.debugDisplaySettingsShown && !c.debugSystemSettingsShown },
                      actual: { "display=\(c.debugDisplaySettingsShown) system=\(c.debugSystemSettingsShown)" })
    }

    // MARK: - 场景三：模式切换
    //
    // Write / Read / Preview 三态各切一次，断言视图显隐正确且预览内容跟着换 ——
    // 模式切换本身会补一次重排（预览里留旧文件内容是修过的 bug）。

    private static func scenarioMode(_ c: MainWindowController, _ doc: URL, _ source: String, _ check: Checker) {
        guard openAndRender(c, doc, check) else { return }

        c.setMode(.write)
        check.expect(c.currentMode == .write && c.debugEditorVisible && !c.debugPreviewVisible,
                     "Write：只显示编辑器",
                     expected: "editor 可见 / preview 隐藏",
                     actual: "editor=\(c.debugEditorVisible) preview=\(c.debugPreviewVisible)")
        check.expect(c.debugEditorText == source,
                     "编辑器内容与磁盘一致",
                     expected: "\(source.count) 字符", actual: "\(c.debugEditorText.count) 字符")

        c.setMode(.preview)
        check.expect(c.currentMode == .preview && c.debugEditorVisible && c.debugPreviewVisible,
                     "Preview：两侧都可见",
                     expected: "editor 可见 / preview 可见",
                     actual: "editor=\(c.debugEditorVisible) preview=\(c.debugPreviewVisible)")
        check.expect(c.debugPreviewText.contains("一、标题层级"),
                     "Preview：预览跟着换成当前文档",
                     expected: "含「一、标题层级」",
                     actual: "预览 \(c.debugPreviewText.count) 字符")

        c.setMode(.read)
        check.expect(c.currentMode == .read && !c.debugEditorVisible && c.debugPreviewVisible,
                     "Read：只显示预览",
                     expected: "editor 隐藏 / preview 可见",
                     actual: "editor=\(c.debugEditorVisible) preview=\(c.debugPreviewVisible)")
        check.expect(c.debugPreviewText.contains("MuM 渲染自检"),
                     "Read：预览内容仍是当前文档",
                     expected: "含「MuM 渲染自检」",
                     actual: "预览 \(c.debugPreviewText.count) 字符")
    }

    // MARK: - 场景四：文档内查找
    //
    // 期望命中数不硬编码 —— demo 文档会改。用与 runFind 相同的匹配规则在
    // 预览文本里数一遍当基准，再断言面板的命中数 / 当前处 / 计数标签读回。

    private static func scenarioFind(_ c: MainWindowController, _ doc: URL, _ check: Checker) {
        guard openAndRender(c, doc, check) else { return }

        let query = "粗体"
        let expected = occurrences(of: query, in: c.debugPreviewText)
        guard check.expect(expected > 0, "文档里确有「\(query)」",
                           expected: ">0 处", actual: "\(expected) 处") else { return }

        c.debugFind(query)
        check.expect(c.isFindingInPreview, "查找条已打开", expected: "isFinding",
                     actual: "未打开")
        check.expect(c.debugPreview.debugFindMatchCount == expected, "命中数",
                     expected: "\(expected)", actual: "\(c.debugPreview.debugFindMatchCount)")
        let index = c.debugPreview.debugFindCurrentIndex
        check.expect((0..<expected).contains(index), "当前处在范围内",
                     expected: "0…\(expected - 1)", actual: "\(index)")
        check.expect(c.debugPreview.debugFindBarCountText == "\(index + 1) / \(expected)",
                     "计数标签读回", expected: "\(index + 1) / \(expected)",
                     actual: c.debugPreview.debugFindBarCountText)

        c.findNext()
        let next = c.debugPreview.debugFindCurrentIndex
        check.expect(next == (index + 1) % expected, "下一处循环前进",
                     expected: "\((index + 1) % expected)", actual: "\(next)")
    }

    // MARK: - 场景五：大纲
    //
    // 断言条目数、首条是文档 H1、位置严格递增且都落在渲染文本内，
    // 最后触发大纲 popover 断言能弹出（重排后大纲必须换新，位置错了跳转会落空）。

    private static func scenarioOutline(_ c: MainWindowController, _ doc: URL, _ check: Checker) {
        guard openAndRender(c, doc, check) else { return }

        let items = c.debugPreview.debugOutlineItems
        guard check.expect(!items.isEmpty, "大纲非空",
                           expected: ">0 条", actual: "0 条") else { return }
        check.expect(items.first?.level == 1 && items.first?.title == "MuM 渲染自检",
                     "首条是文档 H1", expected: "H1「MuM 渲染自检」",
                     actual: items.first.map { "H\($0.level)「\($0.title)」" } ?? "无")
        let ascending = zip(items, items.dropFirst()).allSatisfy { $0.location < $1.location }
        check.expect(ascending, "条目位置严格递增",
                     expected: "递增",
                     actual: items.prefix(6).map(\.location).map(String.init).joined(separator: ","))
        let textLength = (c.debugPreviewText as NSString).length
        check.expect(items.allSatisfy { $0.location < textLength }, "位置都落在渲染文本内",
                     expected: "< \(textLength)",
                     actual: "最大 \(items.map(\.location).max() ?? -1)")

        c.showOutline()
        check.waitFor("大纲 popover 弹出", expected: "isShown",
                      condition: { c.debugPreview.debugOutlinePopoverShown },
                      actual: { "未显示" })
        c.debugPreview.debugCloseOutline()
    }

    // MARK: - 场景六：全局搜索
    //
    // 搜索的终点不是结果列表，是"我已经在读那段话了" —— 所以断言到
    // 点第一条结果后文件打开、reveal 的查找高亮就位为止。

    private static func scenarioSearch(_ c: MainWindowController, _ doc: URL, _ check: Checker) {
        let dir = doc.deletingLastPathComponent()
        guard check.expect(WorkspaceStore.shared.open(url: dir) != nil, "打开 demo 目录为项目",
                           expected: "项目打开成功", actual: "open 返回 nil") else { return }

        let query = "Dijkstra"
        c.debugShowGlobalSearch(prefill: query)
        guard let panel = c.debugGlobalSearchPanel else {
            check.expect(false, "全局搜索面板创建", expected: "面板存在", actual: "nil")
            return
        }
        guard check.waitFor("搜索完成且有结果", expected: "≥1 条命中", timeout: 15,
                            condition: { !panel.debugIsSearching && panel.debugResultCount > 0 },
                            actual: { "searching=\(panel.debugIsSearching)，\(panel.debugResultCount) 条" })
        else { return }
        check.expect(panel.debugFirstHitIsContent, "首条是内容命中（才能定位到行）",
                     expected: "content", actual: "fileName")

        guard let hitURL = panel.debugFirstHitFileURL?.standardizedFileURL else {
            check.expect(false, "首条命中可读", expected: "fileURL 存在", actual: "nil")
            return
        }
        panel.debugOpenFirstResult()
        check.waitFor("点第一条 → 打开命中文件", expected: hitURL.lastPathComponent, timeout: 10,
                      condition: { c.debugCurrentFileURL == hitURL },
                      actual: { c.debugCurrentFileURL?.lastPathComponent ?? "无打开文件" })
        check.waitFor("reveal：文档内查找高亮就位", expected: "查找条打开且命中 >0", timeout: 10,
                      condition: { c.isFindingInPreview && c.debugPreview.debugFindMatchCount > 0 },
                      actual: { "isFinding=\(c.isFindingInPreview)，命中 \(c.debugPreview.debugFindMatchCount)" })
    }

    // MARK: - 场景七：导出（⌘⇧E）
    //
    // 走 ⌘⇧E 保存面板落定后的同一条路径（exportRenderedOrThrow），但写到
    // 临时目录的确定性路径 —— 测试进程不弹 NSSavePanel。断言产物非空且
    // 文件签名正确（PNG 魔数 / %PDF），最后清理临时文件。

    private static func scenarioExport(_ c: MainWindowController, _ doc: URL, _ check: Checker) {
        guard openAndRender(c, doc, check) else { return }
        check.expect(c.canExport, "有打开文档时可导出", expected: "canExport", actual: "不可导出")

        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mum-uitest-export-\(ProcessInfo.processInfo.processIdentifier)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let png = dir.appendingPathComponent("导出.png")
        check.expect(c.debugExport(to: png), "导出 PNG 成功",
                     expected: "写入成功", actual: "debugExport 返回 false")
        check.expect(fileMatches(png.path, magic: [0x89, 0x50, 0x4E, 0x47], minBytes: 1000).ok,
                     "PNG 非空且签名正确", expected: "‰PNG 头 + >1KB",
                     actual: fileMatches(png.path, magic: [0x89, 0x50, 0x4E, 0x47], minBytes: 1000).detail)

        let pdf = dir.appendingPathComponent("导出.pdf")
        check.expect(c.debugExport(to: pdf), "导出 PDF 成功",
                     expected: "写入成功", actual: "debugExport 返回 false")
        check.expect(fileMatches(pdf.path, magic: [0x25, 0x50, 0x44, 0x46], minBytes: 1000).ok,
                     "PDF 非空且签名正确", expected: "%PDF 头 + >1KB",
                     actual: fileMatches(pdf.path, magic: [0x25, 0x50, 0x44, 0x46], minBytes: 1000).detail)
    }

    /// 断言产物：存在、够大、魔数对。返回（结果, 读回描述）
    private static func fileMatches(
        _ path: String, magic: [UInt8], minBytes: Int
    ) -> (ok: Bool, detail: String) {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else {
            return (false, "文件不存在")
        }
        let head = Array(data.prefix(magic.count))
        let ok = data.count >= minBytes && head == magic
        return (ok, "\(data.count) 字节，头部 \(head.map { String(format: "%02X", $0) }.joined())")
    }

    // MARK: - 控件驱动与断言助手

    /// 滑块：设值并触发 action（与拖动同一条 onChange 路径），断言设置与读回
    private static func checkSlider(
        _ row: SettingsSliderRow?, key: String, value: Double,
        in c: MainWindowController, _ check: Checker, setting: KeyPath<MuMSettings, CGFloat>
    ) {
        let name = "滑块 \(key) → \(format(value))"
        guard let row else {
            check.expect(false, name, expected: "控件存在", actual: "不存在")
            return
        }
        row.slider.doubleValue = value
        row.slider.sendAction(row.slider.action, to: row.slider.target)
        let applied = c.debugSettings[keyPath: setting]
        check.expect(applied == CGFloat(value) && row.slider.doubleValue == value, name,
                     expected: "设置=\(format(value))，读回=\(format(value))",
                     actual: "设置=\(format(applied))，读回=\(format(row.slider.doubleValue))")
    }

    /// 分段控件：选中并触发 action，断言设置与读回
    private static func checkSegment<T: Equatable>(
        _ row: SettingsSegmentedRow?, key: String, index: Int, expected: T,
        in c: MainWindowController, _ check: Checker, setting: KeyPath<MuMSettings, T>
    ) {
        let name = "分段 \(key) → 第 \(index + 1) 项"
        guard let row else {
            check.expect(false, name, expected: "控件存在", actual: "不存在")
            return
        }
        row.control.selectedSegment = index
        row.control.sendAction(row.control.action, to: row.control.target)
        let applied = c.debugSettings[keyPath: setting]
        check.expect(applied == expected && row.control.selectedSegment == index, name,
                     expected: "设置=\(expected)，读回=\(index)",
                     actual: "设置=\(applied)，读回=\(row.control.selectedSegment)")
    }

    /// 开关：performClick 翻到目标状态（与点击同一条路径），断言设置与读回
    private static func checkToggle(
        _ row: SettingsToggleRow?, key: String, want: Bool,
        in c: MainWindowController, _ check: Checker, setting: KeyPath<MuMSettings, Bool>
    ) {
        let name = "开关 \(key) → \(want ? "开" : "关")"
        guard let row else {
            check.expect(false, name, expected: "控件存在", actual: "不存在")
            return
        }
        if (row.button.state == .on) != want { row.button.performClick(nil) }
        let applied = c.debugSettings[keyPath: setting]
        check.expect(applied == want && (row.button.state == .on) == want, name,
                     expected: "设置=\(want)，读回=\(want)",
                     actual: "设置=\(applied)，读回=\(row.button.state == .on)")
    }

    /// 打开文档并等渲染完成（各场景共用的前置条件）。轮询而非睡死。
    @discardableResult
    private static func openAndRender(
        _ c: MainWindowController, _ doc: URL, _ check: Checker
    ) -> Bool {
        if c.debugCurrentFileURL != doc { c.open(url: doc) }
        c.setMode(.read)
        return check.waitFor("打开文档并渲染", expected: "预览含「MuM 渲染自检」", timeout: 10,
                             condition: { c.debugPreviewText.contains("MuM 渲染自检") },
                             actual: { "预览 \(c.debugPreviewText.count) 字符" })
    }

    /// 与 PreviewViewController.runFind 相同的匹配规则：大小写与变音符不敏感
    private static func occurrences(of query: String, in text: String) -> Int {
        let haystack = text as NSString
        var count = 0
        var searchRange = NSRange(location: 0, length: haystack.length)
        while searchRange.length > 0 {
            let found = haystack.range(
                of: query, options: [.caseInsensitive, .diacriticInsensitive], range: searchRange)
            guard found.location != NSNotFound else { break }
            count += 1
            let next = found.location + max(found.length, 1)
            guard next < haystack.length else { break }
            searchRange = NSRange(location: next, length: haystack.length - next)
        }
        return count
    }

    /// 确定性等待：轮询条件直到满足或超时。不用固定时长睡眠 ——
    /// 条件早满足就早继续，超时由调用方记为失败
    @discardableResult
    static func wait(_ timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() {
            if Date() >= deadline { return condition() }
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }
        return true
    }

    private static func format(_ value: Double) -> String {
        String(format: "%g", value)
    }

    private static func format(_ value: CGFloat) -> String {
        format(Double(value))
    }

    /// 一个场景的全部步骤结果
    private final class Checker {
        struct Step {
            let index: Int
            let name: String
            let ok: Bool
            let expected: String
            let actual: String
        }

        let name: String
        private(set) var steps: [Step] = []

        init(name: String) { self.name = name }

        @discardableResult
        func expect(_ condition: Bool, _ stepName: String, expected: String, actual: String) -> Bool {
            steps.append(Step(index: steps.count + 1, name: stepName,
                              ok: condition, expected: expected, actual: actual))
            if condition {
                print("  ✅ \(stepName)")
            } else {
                print("  ❌ 第 \(steps.count) 步 \(stepName)：期望 \(expected)，实际 \(actual)")
            }
            return condition
        }

        @discardableResult
        func waitFor(_ stepName: String, expected: String, timeout: TimeInterval = 5,
                     condition: () -> Bool, actual: () -> String) -> Bool {
            let ok = UITestRunner.wait(timeout, condition)
            return expect(ok, stepName, expected: expected, actual: actual())
        }
    }
}
