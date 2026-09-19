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

        // 窗口已上屏，再恢复内容。有外部打开请求（双击 / Dock 拖入）时优先它 ——
        // 用户点的是那个文件，先恢复上次会话的遗留文件是白付一次加载和渲染
        controller.restoreActiveWorkspace(skippingFileRestore: !pendingOpenURLs.isEmpty)

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

        // 启动后静默检查一次更新：延迟几秒，不挡启动路径；失败安静吞掉（reading is the point），
        // 有新版本也只出一条不抢焦点的提示条
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            self?.checkForUpdatesSilently()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// ⌘Q / 菜单退出：有未保存修改时先确认，和关窗（windowShouldClose）同一条路径。
    /// 原来这里没人守 —— confirmDiscardIfNeeded 只挂在 open/close/reload/mode 四处，
    /// ⌘Q 直接全丢（审计 D-1）。
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let controller = mainWindowController else { return .terminateNow }
        return controller.confirmDiscardIfNeeded() ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) {
        mainWindowController?.saveReadingPosition()
    }

    /// 从访达双击 / `open -a MuM <路径>` 打开
    func application(_ application: NSApplication, open urls: [URL]) {
        LaunchTimer.mark("AppDelegate 收到 open 事件（\(urls.count) 个 URL）")
        // 打开事件可能早于 applicationDidFinishLaunching 到达，那时窗口还没建好。
        // 不排队的话这些路径会被静默丢掉 —— 表现就是"双击文件没反应，只弹出上次的文档"。
        guard let controller = mainWindowController else {
            pendingOpenURLs.append(contentsOf: urls)
            return
        }
        open(urls, with: controller)
    }

    private func open(_ urls: [URL], with controller: MainWindowController) {
        // 打开必须把人带到窗口前。应用已在运行时，open 事件走的是这里而不是
        // didFinishLaunching —— 那里面的激活不会再来一次，窗口可能还埋在后面。
        controller.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        for url in urls {
            controller.openIncoming(url)
        }
    }

    @objc private func workspaceListChanged() {
        guard let menuSet else { return }
        MainMenuBuilder.rebuildProjectMenu(menuSet.projectMenu, target: self)
    }

    // MARK: - 关于

    private var aboutWindowController: AboutWindowController?

    @objc func showAbout(_ sender: Any?) {
        let controller = aboutWindowController ?? AboutWindowController()
        aboutWindowController = controller
        controller.present(relativeTo: mainWindowController?.window)
    }

    // MARK: - 文件

    @objc func newDocument(_ sender: Any?) {
        mainWindowController?.newDocument()
    }

    @objc func newFolder(_ sender: Any?) {
        mainWindowController?.newFolder()
    }

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

    @objc func exportDocument(_ sender: Any?) {
        mainWindowController?.exportDocument()
    }

    @objc func refreshFileTree(_ sender: Any?) {
        mainWindowController?.refreshFileTree()
    }

    // MARK: - 查找

    @objc func showPreviewFind(_ sender: Any?) {
        mainWindowController?.showPreviewFind()
    }

    @objc func showGlobalSearch(_ sender: Any?) {
        mainWindowController?.showGlobalSearch()
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

    @objc func goBack(_ sender: Any?) {
        mainWindowController?.goBack()
    }

    @objc func goForward(_ sender: Any?) {
        mainWindowController?.goForward()
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

    @objc func showQuickOpen(_ sender: Any?) {
        mainWindowController?.showQuickOpen()
    }

    // MARK: - 帮助

    // MARK: - 更新检查

    private var updateBannerController: UpdateBannerViewController?

    /// 帮助 → 检查更新…：手动触发，三种结果都要明说
    @objc func checkForUpdates(_ sender: Any?) {
        UpdateChecker.check { [weak self] result in
            guard let self else { return }
            switch result {
            case .available(let update):
                self.presentUpdateBanner(update)
            case .upToDate:
                let alert = NSAlert()
                alert.messageText = "已是最新版本"
                alert.informativeText = "v\(UpdateChecker.currentVersion) 是当前发布的最新版。"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "好")
                if let window = self.mainWindowController?.window {
                    alert.beginSheetModal(for: window)
                } else {
                    alert.runModal()
                }
            case .failed:
                let alert = NSAlert()
                alert.messageText = "暂时连不上更新源"
                alert.informativeText = "检查更新需要访问 GitHub，请稍后再试。"
                alert.alertStyle = .informational
                alert.addButton(withTitle: "好")
                if let window = self.mainWindowController?.window {
                    alert.beginSheetModal(for: window)
                } else {
                    alert.runModal()
                }
            }
        }
    }

    /// 启动静默检查：失败吞掉；用户忽略过的版本不再提示
    private func checkForUpdatesSilently() {
        UpdateChecker.check { [weak self] result in
            guard let self, case .available(let update) = result else { return }
            let settings = SettingsStore.load()
            guard update.version != settings.ignoredUpdateVersion else { return }
            self.presentUpdateBanner(update)
        }
    }

    private func presentUpdateBanner(_ update: UpdateChecker.AvailableUpdate) {
        guard let window = mainWindowController?.window else { return }
        // 已经挂着就不重复挂
        guard updateBannerController == nil,
              !window.titlebarAccessoryViewControllers.contains(where: { $0 === updateBannerController })
        else { return }
        let banner = UpdateBannerViewController(update: update)
        banner.onIgnore = {
            var settings = SettingsStore.load()
            settings.ignoredUpdateVersion = update.version
            SettingsStore.save(settings)
        }
        banner.onDismiss = { [weak self] in
            self?.updateBannerController = nil
        }
        updateBannerController = banner
        window.addTitlebarAccessoryViewController(banner)
    }

    private var shortcutsHelpController: ShortcutsHelpWindowController?


    @objc func showHelp(_ sender: Any?) {
        let controller = shortcutsHelpController ?? ShortcutsHelpWindowController()
        shortcutsHelpController = controller
        controller.present(relativeTo: mainWindowController?.window)
    }

    /// 帮助 → 反馈问题或建议…：直达反馈模板，并把版本 / macOS / 芯片预填进表单
    /// （issue forms 支持用字段 id 作 URL 参数预填）—— 判断问题时第一个要问的就是版本，
    /// 用户不会记得自己跑的是哪版，能自动带上的就别让人填
    @objc func showFeedback(_ sender: Any?) {
        var components = URLComponents(string: "https://github.com/ice5kysl/MuM/issues/new")!
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var queryItems = [URLQueryItem(name: "template", value: "feedback.yml")]
        if !version.isEmpty {
            queryItems.append(URLQueryItem(name: "version", value: "v\(version)"))
        }
        queryItems.append(URLQueryItem(
            name: "macos",
            value: "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) / \(Self.archName)"
        ))
        components.queryItems = queryItems
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    private static var archName: String {
        #if arch(arm64)
        return "Apple Silicon"
        #else
        return "Intel"
        #endif
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

        case #selector(exportDocument(_:)):
            return mainWindowController?.canExport ?? false

        case #selector(reloadDocument(_:)),
             #selector(closeDocument(_:)),
             #selector(revealInFinder(_:)):
            return mainWindowController?.hasOpenDocument ?? false

        case #selector(goBack(_:)):
            return mainWindowController?.canGoBack ?? false

        case #selector(goForward(_:)):
            return mainWindowController?.canGoForward ?? false

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
             #selector(focusFileFilter(_:)),
             #selector(showQuickOpen(_:)),
             #selector(showGlobalSearch(_:)):
            return WorkspaceStore.shared.count > 0

        default:
            return true
        }
    }
}
