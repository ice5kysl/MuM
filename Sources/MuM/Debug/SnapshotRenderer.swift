import AppKit

/// 离屏渲染：把整个窗口渲染成 PNG，不依赖屏幕是否点亮，也不弹窗。
///
/// 用途有两个：一是在没有可用显示环境（锁屏、SSH、CI）时检查界面；二是给
/// 视觉回归留一个可比较的产物。
///
/// 用法：`MuM --snapshot /path/to/out.png`
enum SnapshotRenderer {

    static func run(arguments: [String]) -> Int32 {
        // 单独渲染设置面板：齿轮在底栏，锁屏 / 无鼠标时点不到，用它来核对面板布局
        if let flagIndex = arguments.firstIndex(of: "--snapshot-settings"),
           flagIndex + 1 < arguments.count {
            let dark = arguments.contains("--dark")
            let system = arguments.contains("--system")
            return snapshotSettings(to: arguments[flagIndex + 1], dark: dark, system: system)
        }

        guard let flagIndex = arguments.firstIndex(of: "--snapshot"),
              flagIndex + 1 < arguments.count else {
            FileHandle.standardError.write("用法：MuM --snapshot <输出路径.png>\n".data(using: .utf8)!)
            return 2
        }
        let outputURL = URL(fileURLWithPath: arguments[flagIndex + 1])

        // AppKit 的视图体系需要 NSApplication 存在才能工作，但不需要 run()
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        // 必须钉住外观：进程没有真实窗口时，`.labelColor` 这类语义色可能解析成白色，
        // 于是白底白字 —— 离屏图看着"文字全丢了"，其实只是颜色解析跑偏。
        // 传 `--dark` 可以渲染暗色版本。
        app.appearance = NSAppearance(named: arguments.contains("--dark") ? .darkAqua : .aqua)

        let controller = MainWindowController()
        guard let window = controller.window, let content = window.contentView else {
            FileHandle.standardError.write("无法建立窗口\n".data(using: .utf8)!)
            return 1
        }

        window.setContentSize(MuMDesign.defaultWindowContentSize)

        // 顺序很重要：先让首次布局跑完（面板宽度和分隔线位置都在这一步定下来），
        // 再执行折叠 —— 这才是用户实际操作的顺序。反过来在首次布局前就折起一栏，
        // NSSplitView 还没有任何位置信息，会把空间分错。
        RunLoop.main.run(until: Date().addingTimeInterval(0.4))

        // 模拟弹出文档大纲：`--outline`
        if arguments.contains("--outline") {
            controller.debugOutline()
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        }

        // 模拟一次预览查找：`--find <查询词>`
        if let index = arguments.firstIndex(of: "--find"), index + 1 < arguments.count {
            controller.debugFind(arguments[index + 1])
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        }

        // 模拟"运行时打开显示行号" —— 和启动时读设置是两条不同的路径
        if arguments.contains("--toggle-lines") {
            controller.debugApplySettings { $0.showsLineNumbers = true }
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        }

        // 可选：`--collapse 0,1` 折起指定面板，用来验证折叠后的界面
        if let flagIndex = arguments.firstIndex(of: "--collapse"), flagIndex + 1 < arguments.count {
            let panes = arguments[flagIndex + 1].split(separator: ",").compactMap { Int($0) }
            for pane in panes {
                switch pane {
                case 0: controller.toggleProjects()
                case 1: controller.toggleFileTree()
                default: break
                }
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        }

        print("面板：项目列表=\(controller.isProjectsVisible ? "展开" : "折叠")，目录树=\(controller.isFileTreeVisible ? "展开" : "折叠")")
        print("窗口 \(NSStringFromRect(window.frame))  内容视图 \(NSStringFromRect(content.bounds))")

        if ProcessInfo.processInfo.environment["MUM_LAYOUT_DEBUG"] != nil {
            print("设置：\(controller.debugSettingsDescription)")
            print("大纲：\(controller.debugOutlineDescription)")
            print("视图树：")
            print(controller.dumpViewTree())
        }

        // 预览渲染是异步去抖的（打字时每 110ms 才重排一次），不跑一小段 runloop
        // 的话快照里只会看到 PreviewViewController 的初始占位文字。
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        // 不走 orderFront，所以手动把布局推完：先让视图树布局，再给控制器一次机会
        // 摆好分隔线（朴素 NSSplitView 的位置是在 viewDidLayout 里设的）。
        content.layoutSubtreeIfNeeded()
        if let rootViewController = window.contentViewController {
            rootViewController.view.layoutSubtreeIfNeeded()
        }
        content.layoutSubtreeIfNeeded()

        guard let rep = content.bitmapImageRepForCachingDisplay(in: content.bounds) else {
            FileHandle.standardError.write("无法创建位图\n".data(using: .utf8)!)
            return 1
        }
        content.cacheDisplay(in: content.bounds, to: rep)

        guard let data = rep.representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write("无法编码 PNG\n".data(using: .utf8)!)
            return 1
        }

        do {
            try data.write(to: outputURL)
        } catch {
            FileHandle.standardError.write("写入失败：\(error.localizedDescription)\n".data(using: .utf8)!)
            return 1
        }

        print("已渲染 \(Int(content.bounds.width))×\(Int(content.bounds.height)) → \(outputURL.path)")
        return 0
    }

    /// 把设置面板单独渲染成 PNG
    private static func snapshotSettings(to path: String, dark: Bool, system: Bool) -> Int32 {
        let app = NSApplication.shared
        app.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)

        let panel: NSViewController = system
            ? SystemSettingsPanelViewController(settings: MuMSettings())
            : SettingsPanelViewController(settings: MuMSettings())
        // 先碰一下 view 触发 loadView —— preferredContentSize 是在那里算出来的
        _ = panel.view
        // 面板本身不画背景（真实 popover 由系统材质打底）。离屏渲染没有那层材质，
        // 就成了"白字落在白底上"，看着像文字全丢了。这里补一层窗口底色。
        panel.view.wantsLayer = true
        panel.view.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let size = panel.preferredContentSize
        panel.view.frame = NSRect(origin: .zero, size: size)
        panel.view.layoutSubtreeIfNeeded()
        // 文本控件要先走一轮绘制，否则 cacheDisplay 抓到的是一张没有文字的图
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        panel.view.layoutSubtreeIfNeeded()

        guard let rep = panel.view.bitmapImageRepForCachingDisplay(in: panel.view.bounds) else {
            FileHandle.standardError.write("无法创建位图\n".data(using: .utf8)!)
            return 1
        }
        panel.view.cacheDisplay(in: panel.view.bounds, to: rep)

        guard let data = rep.representation(using: .png, properties: [:]) else { return 1 }
        do {
            try data.write(to: URL(fileURLWithPath: path))
        } catch {
            FileHandle.standardError.write("写入失败：\(error.localizedDescription)\n".data(using: .utf8)!)
            return 1
        }

        print("设置面板 \(Int(size.width))×\(Int(size.height)) → \(path)")
        return 0
    }
}
