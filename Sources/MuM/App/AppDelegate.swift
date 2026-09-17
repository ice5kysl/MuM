import AppKit

/// 应用生命周期与菜单动作的分发点。
///
/// 菜单动作统一在这里实现，再转发给 `MainWindowController`：菜单栏在 AppKit 里是
/// 全局的，而窗口控制器不出现在所有响应链上，直接挂在 delegate 上最省心，也让
/// `validateMenuItem` 能集中判断"当前有没有文件可保存"这类状态。
final class AppDelegate: NSObject, NSApplicationDelegate {

    private var mainWindowController: MainWindowController?
    private var menuSet: MainMenuBuilder.MenuSet?
    /// 窗口就绪之前收到的打开请求
    private var pendingOpenURLs: [URL] = []

    // MARK: - 生命周期

    func applicationDidFinishLaunching(_ notification: Notification) {
        LaunchTimer.mark("NSApplication 就绪，进入 didFinishLaunching")
        NSApp.appearance = nil // 跟随系统明暗模式

        let menuSet = MainMenuBuilder.build(target: self)
        self.menuSet = menuSet
        NSApp.mainMenu = menuSet.mainMenu

        LaunchTimer.mark("开始构建 MainWindowController")
        let controller = MainWindowController()
        LaunchTimer.mark("MainWindowController 构建完成")
        mainWindowController = controller
        LaunchTimer.mark("开始 showWindow")
        controller.showWindow(nil)
        LaunchTimer.mark("showWindow 返回（窗口已上屏）")
        controller.window?.makeKeyAndOrderFront(nil)

        NSApp.activate(ignoringOtherApps: true)

        // 补上窗口就绪之前到达的打开请求
        if !pendingOpenURLs.isEmpty {
            let urls = pendingOpenURLs
            pendingOpenURLs.removeAll()
            open(urls, with: controller)
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(workspaceListChanged),
            name: .mumWorkspaceListChanged,
            object: nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        mainWindowController?.saveReadingPosition()
    }

    /// 从访达双击 / `open -a MuM <路径>` 打开
    func application(_ application: NSApplication, open urls: [URL]) {
        // 打开事件可能早于 applicationDidFinishLaunching 到达，那时窗口还没建好。
        // 不排队的话这些路径会被静默丢掉 —— 表现就是"双击文件没反应，只弹出上次的文档"。
        guard let controller = mainWindowController else {
            pendingOpenURLs.append(contentsOf: urls)
            return
        }
        open(urls, with: controller)
    }

    private func open(_ urls: [URL], with controller: MainWindowController) {
        for url in urls {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { continue }

            if isDirectory.boolValue {
                WorkspaceStore.shared.open(url: url)
            } else {
                // Info.plist 里声明了 Markdown 文档类型，双击 .md 也得能打开
                controller.openFileFromOutside(url)
            }
        }
    }

    @objc private func workspaceListChanged() {
        guard let menuSet else { return }
        MainMenuBuilder.rebuildProjectMenu(menuSet.projectMenu, target: self)
    }

    // MARK: - 文件

    @objc func openFolder(_ sender: Any?) {
        WorkspaceStore.shared.promptForFolder()
    }

    @objc func closeProject(_ sender: Any?) {
        WorkspaceStore.shared.closeActive()
    }

    @objc func saveDocument(_ sender: Any?) {
        mainWindowController?.saveDocument()
    }

    @objc func reloadDocument(_ sender: Any?) {
        mainWindowController?.reloadDocument()
    }

    @objc func closeDocument(_ sender: Any?) {
        mainWindowController?.closeDocument()
    }

    @objc func refreshFileTree(_ sender: Any?) {
        mainWindowController?.refreshFileTree()
    }

    // MARK: - 查找

    @objc func showPreviewFind(_ sender: Any?) {
        mainWindowController?.showPreviewFind()
    }

    @objc func showOutline(_ sender: Any?) {
        mainWindowController?.showOutline()
    }

    @objc func findNext(_ sender: Any?) {
        mainWindowController?.findNext()
    }

    @objc func findPrevious(_ sender: Any?) {
        mainWindowController?.findPrevious()
    }

    @objc func revealInFinder(_ sender: Any?) {
        mainWindowController?.revealInFinder()
    }


    // MARK: - 项目切换

    @objc func selectProject(_ sender: NSMenuItem) {
        WorkspaceStore.shared.activateShortcut(sender.tag)
    }

    @objc func nextProject(_ sender: Any?) {
        WorkspaceStore.shared.activateNext()
    }

    @objc func previousProject(_ sender: Any?) {
        WorkspaceStore.shared.activatePrevious()
    }

    @objc func moveProjectLeft(_ sender: Any?) {
        WorkspaceStore.shared.moveActive(by: -1)
    }

    @objc func moveProjectRight(_ sender: Any?) {
        WorkspaceStore.shared.moveActive(by: 1)
    }

    // MARK: - 显示

    @objc func toggleProjects(_ sender: Any?) {
        mainWindowController?.toggleProjects()
    }

    @objc func toggleFileTree(_ sender: Any?) {
        mainWindowController?.toggleFileTree()
    }

    // MARK: - 呈现模式

    @objc func setWriteMode(_ sender: Any?) {
        mainWindowController?.setMode(.write)
    }

    @objc func setReadMode(_ sender: Any?) {
        mainWindowController?.setMode(.read)
    }

    @objc func setPreviewMode(_ sender: Any?) {
        mainWindowController?.setMode(.preview)
    }

    @objc func increasePreviewFont(_ sender: Any?) {
        mainWindowController?.changePreviewFontSize(by: 1)
    }

    @objc func decreasePreviewFont(_ sender: Any?) {
        mainWindowController?.changePreviewFontSize(by: -1)
    }

    @objc func resetPreviewFont(_ sender: Any?) {
        mainWindowController?.resetPreviewFontSize()
    }

    @objc func focusFileFilter(_ sender: Any?) {
        mainWindowController?.focusFileFilter()
    }

    // MARK: - 帮助

    @objc func showHelp(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "MuM 快捷键"
        alert.informativeText = """
        项目
          ⌘O          打开项目文件夹
          ⌘1 … ⌘9     切换到第 N 个项目
          ⇧⌘[ / ⇧⌘]   上一个 / 下一个项目
          ⌥⌘[ / ⌥⌘]   把当前项目左移 / 右移（固化 ⌘数字 的位置）
          ⇧⌘W         关闭当前项目

        文件
          ⌘P          聚焦文件过滤框
          ⌘S          保存
          ⌘R          从磁盘重新载入
          ⌘W          关闭当前文件
          ⇧⌘R         刷新文件树
          ⇧⌘J         在访达中显示

        呈现方式
          ⌥⌘1         Write — 写 Markdown 源码
          ⌥⌘2         Read — 阅读渲染结果
          ⌥⌘3         Preview — 源码与渲染并排对照

        面板
          ⌘0          显示 / 隐藏项目列表
          ⌥⌘0         显示 / 隐藏目录树
          ⌘+ / ⌘-     预览字号
          ⌃⌘F         全屏幕
        """
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

// MARK: - 菜单可用性

extension AppDelegate: NSMenuItemValidation {

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {

        case #selector(selectProject(_:)):
            menuItem.state = menuItem.tag == WorkspaceStore.shared.activeIndex ? .on : .off
            return WorkspaceStore.shared.workspaces.indices.contains(menuItem.tag)

        case #selector(closeProject(_:)):
            return WorkspaceStore.shared.count > 0

        case #selector(nextProject(_:)),
             #selector(previousProject(_:)),
             #selector(moveProjectLeft(_:)),
             #selector(moveProjectRight(_:)):
            return WorkspaceStore.shared.count > 1

        case #selector(saveDocument(_:)):
            return mainWindowController?.hasOpenDocument ?? false

        case #selector(reloadDocument(_:)),
             #selector(closeDocument(_:)),
             #selector(revealInFinder(_:)):
            return mainWindowController?.hasOpenDocument ?? false

        case #selector(toggleProjects(_:)):
            menuItem.state = (mainWindowController?.isProjectsVisible ?? false) ? .on : .off
            return true

        case #selector(toggleFileTree(_:)):
            menuItem.state = (mainWindowController?.isFileTreeVisible ?? false) ? .on : .off
            return WorkspaceStore.shared.count > 0

        case #selector(setWriteMode(_:)):
            menuItem.state = mainWindowController?.currentMode == .write ? .on : .off
            return mainWindowController?.hasOpenDocument ?? false

        case #selector(setReadMode(_:)):
            menuItem.state = mainWindowController?.currentMode == .read ? .on : .off
            return mainWindowController?.hasOpenDocument ?? false

        case #selector(setPreviewMode(_:)):
            menuItem.state = mainWindowController?.currentMode == .preview ? .on : .off
            return mainWindowController?.hasOpenDocument ?? false

        case #selector(refreshFileTree(_:)),
             #selector(focusFileFilter(_:)):
            return WorkspaceStore.shared.count > 0

        default:
            return true
        }
    }
}
