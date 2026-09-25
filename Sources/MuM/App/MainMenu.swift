import AppKit

/// 原生菜单栏。快捷键的分配原则：把最常用的动作压在左手单手可达的位置，
/// 并且和 Sublime / VS Code 的习惯尽量一致，降低肌肉记忆迁移成本。
enum MainMenuBuilder {

    struct MenuSet {
        let mainMenu: NSMenu
        let projectMenu: NSMenu
    }

    static func build(target: AppDelegate) -> MenuSet {
        let mainMenu = NSMenu()

        let appMenu = NSMenu()
        let aboutItem = NSMenuItem(title: "关于 MuM", action: #selector(AppDelegate.showAbout(_:)), keyEquivalent: "")
        aboutItem.target = target
        appMenu.addItem(aboutItem)
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "隐藏 MuM", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")

        let hideOthers = NSMenuItem(title: "隐藏其他", action: #selector(NSApplication.hideOtherApplications(_:)), keyEquivalent: "h")
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(hideOthers)
        appMenu.addItem(withTitle: "显示全部", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 MuM", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        let appItem = NSMenuItem()
        appItem.submenu = appMenu
        mainMenu.addItem(appItem)

        mainMenu.addItem(fileMenu(target: target))
        mainMenu.addItem(editMenu(target: target))

        let projectMenu = projectMenu(target: target)
        mainMenu.addItem(projectMenuItem(projectMenu))

        mainMenu.addItem(viewMenu(target: target))

        let windowMenu = windowMenu(target: target)
        mainMenu.addItem(windowMenuItem(windowMenu))
        NSApp.windowsMenu = windowMenu

        mainMenu.addItem(helpMenu())

        return MenuSet(mainMenu: mainMenu, projectMenu: projectMenu)
    }

    // MARK: - 文件

    private static func fileMenu(target: AppDelegate) -> NSMenuItem {
        let menu = NSMenu(title: "文件")
        // 总是可用：有项目建进项目，无项目弹保存面板 —— 所以不进 validateMenuItem 的置灰列表
        menu.addItem(item("新建文件", #selector(AppDelegate.newDocument(_:)), "n", target: target))
        menu.addItem(.separator())
        menu.addItem(item("打开项目…", #selector(AppDelegate.openFolder(_:)), "o", target: target))
        menu.addItem(item("关闭当前项目", #selector(AppDelegate.closeProject(_:)), "w", modifiers: [.command, .shift], target: target))
        menu.addItem(.separator())
        menu.addItem(item("保存", #selector(AppDelegate.saveDocument(_:)), "s", target: target))
        menu.addItem(item("从磁盘重新载入", #selector(AppDelegate.reloadDocument(_:)), "r", target: target))
        menu.addItem(item("关闭当前文件", #selector(AppDelegate.closeDocument(_:)), "w", target: target))
        menu.addItem(.separator())
        menu.addItem(item("导出…", #selector(AppDelegate.exportDocument(_:)), "e", modifiers: [.command, .shift], target: target))
        menu.addItem(.separator())
        menu.addItem(item("刷新文件树", #selector(AppDelegate.refreshFileTree(_:)), "r", modifiers: [.command, .shift], target: target))
        menu.addItem(.separator())
        menu.addItem(item("在访达中显示", #selector(AppDelegate.revealInFinder(_:)), "j", modifiers: [.command, .shift], target: target))
        menu.addItem(.separator())
        menu.addItem(item("返回上一篇", #selector(AppDelegate.goBack(_:)), "[", target: target))
        menu.addItem(item("前进下一篇", #selector(AppDelegate.goForward(_:)), "]", target: target))

        let holder = NSMenuItem(title: "文件", action: nil, keyEquivalent: "")
        holder.submenu = menu
        return holder
    }

    // MARK: - 编辑

    private static func editMenu(target: AppDelegate) -> NSMenuItem {
        let menu = NSMenu(title: "编辑")
        menu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "重做", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        menu.addItem(redo)
        menu.addItem(.separator())
        menu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        menu.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        menu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        menu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        menu.addItem(.separator())
        menu.addItem(withTitle: "查找…", action: #selector(NSTextView.performFindPanelAction(_:)), keyEquivalent: "f")
        menu.addItem(item("快速打开…", #selector(AppDelegate.showQuickOpen(_:)), "p", target: target))
        menu.addItem(item("过滤文件…", #selector(AppDelegate.focusFileFilter(_:)), "", target: target))
        menu.addItem(.separator())
        menu.addItem(item("在预览中查找…", #selector(AppDelegate.showPreviewFind(_:)), "f", target: target))
        menu.addItem(item("全局搜索…", #selector(AppDelegate.showGlobalSearch(_:)), "f", modifiers: [.command, .shift], target: target))
        menu.addItem(item("大纲栏", #selector(AppDelegate.toggleTOC(_:)), "o", modifiers: [.command, .shift], target: target))
        menu.addItem(item("查找下一处", #selector(AppDelegate.findNext(_:)), "g", target: target))
        menu.addItem(item("查找上一处", #selector(AppDelegate.findPrevious(_:)), "g", modifiers: [.command, .shift], target: target))

        let holder = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        holder.submenu = menu
        return holder
    }

    // MARK: - 项目

    private static func projectMenu(target: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "项目")
        rebuildProjectMenu(menu, target: target)
        return menu
    }

    private static func projectMenuItem(_ menu: NSMenu) -> NSMenuItem {
        let holder = NSMenuItem(title: "项目", action: nil, keyEquivalent: "")
        holder.submenu = menu
        return holder
    }

    /// 项目列表会变，这个菜单每次变更后重建
    static func rebuildProjectMenu(_ menu: NSMenu, target: AppDelegate) {
        menu.removeAllItems()

        let store = WorkspaceStore.shared
        menu.addItem(item("打开项目…", #selector(AppDelegate.openFolder(_:)), "o", target: target))

        if !store.workspaces.isEmpty {
            menu.addItem(.separator())
        }

        for (index, workspace) in store.workspaces.enumerated() {
            let key = index < 9 ? "\(index + 1)" : ""
            let entry = item(
                workspace.name,
                #selector(AppDelegate.selectProject(_:)),
                key,
                target: target
            )
            entry.tag = index
            entry.toolTip = workspace.displayPath
            if index == store.activeIndex {
                entry.state = .on
            }
            menu.addItem(entry)
        }

        if store.count > 1 {
            menu.addItem(.separator())
            menu.addItem(item("下一个项目", #selector(AppDelegate.nextProject(_:)), "]", modifiers: [.command, .shift], target: target))
            menu.addItem(item("上一个项目", #selector(AppDelegate.previousProject(_:)), "[", modifiers: [.command, .shift], target: target))
            menu.addItem(.separator())
            menu.addItem(item("当前项目左移", #selector(AppDelegate.moveProjectLeft(_:)), "[", modifiers: [.command, .option], target: target))
            menu.addItem(item("当前项目右移", #selector(AppDelegate.moveProjectRight(_:)), "]", modifiers: [.command, .option], target: target))
        }

        menu.addItem(.separator())
        menu.addItem(item("关闭当前项目", #selector(AppDelegate.closeProject(_:)), "w", modifiers: [.command, .shift], target: target))
    }

    // MARK: - 显示

    private static func viewMenu(target: AppDelegate) -> NSMenuItem {
        let menu = NSMenu(title: "显示")

        menu.addItem(item("项目列表", #selector(AppDelegate.toggleProjects(_:)), "0", target: target))
        menu.addItem(item("目录树", #selector(AppDelegate.toggleFileTree(_:)), "0", modifiers: [.command, .option], target: target))

        menu.addItem(.separator())

        // 三种呈现方式。⌘⌥1/2/3 而不是 ⌘1/2/3：后者留给项目切换，
        // 而 ⇧⌘3 之类会被系统的截图快捷键抢走。
        menu.addItem(item("Write — 写源码", #selector(AppDelegate.setWriteMode(_:)), "1", modifiers: [.command, .option], target: target))
        menu.addItem(item("Read — 阅读", #selector(AppDelegate.setReadMode(_:)), "2", modifiers: [.command, .option], target: target))
        menu.addItem(item("Preview — 并排对照", #selector(AppDelegate.setPreviewMode(_:)), "3", modifiers: [.command, .option], target: target))

        menu.addItem(.separator())
        menu.addItem(item("放大预览字号", #selector(AppDelegate.increasePreviewFont(_:)), "+", target: target))
        menu.addItem(item("缩小预览字号", #selector(AppDelegate.decreasePreviewFont(_:)), "-", target: target))
        menu.addItem(item("重置预览字号", #selector(AppDelegate.resetPreviewFont(_:)), "0", modifiers: [.command, .shift], target: target))
        menu.addItem(.separator())

        let fullScreen = NSMenuItem(title: "进入全屏幕", action: #selector(NSWindow.toggleFullScreen(_:)), keyEquivalent: "f")
        fullScreen.keyEquivalentModifierMask = [.command, .control]
        menu.addItem(fullScreen)

        let holder = NSMenuItem(title: "显示", action: nil, keyEquivalent: "")
        holder.submenu = menu
        return holder
    }

    // MARK: - 窗口

    private static func windowMenu(target: AppDelegate) -> NSMenu {
        let menu = NSMenu(title: "窗口")
        menu.addItem(withTitle: "最小化", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        menu.addItem(withTitle: "缩放", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "前置全部窗口", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        return menu
    }

    private static func windowMenuItem(_ menu: NSMenu) -> NSMenuItem {
        let holder = NSMenuItem(title: "窗口", action: nil, keyEquivalent: "")
        holder.submenu = menu
        return holder
    }

    // MARK: - 帮助

    private static func helpMenu() -> NSMenuItem {
        let menu = NSMenu(title: "帮助")
        let item = NSMenuItem(title: "MuM 使用说明", action: #selector(AppDelegate.showHelp(_:)), keyEquivalent: "?")
        item.target = NSApp.delegate as? AppDelegate
        item.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular))
        menu.addItem(item)

        // 更新检查：紧跟使用说明之后 —— 「我跑的到底是不是最新版」是帮助场景的第一问
        let update = NSMenuItem(title: "检查更新…", action: #selector(AppDelegate.checkForUpdates(_:)), keyEquivalent: "")
        update.target = NSApp.delegate as? AppDelegate
        update.image = NSImage(systemSymbolName: "arrow.triangle.2.circlepath", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular))
        menu.addItem(update)

        // 反馈入口：开源项目的生命线，放帮助菜单（macOS 惯例位置）
        let feedback = NSMenuItem(title: "反馈问题或建议…", action: #selector(AppDelegate.showFeedback(_:)), keyEquivalent: "")
        feedback.target = NSApp.delegate as? AppDelegate
        feedback.image = NSImage(systemSymbolName: "bubble.left", accessibilityDescription: nil)?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: 12, weight: .regular))
        menu.addItem(feedback)

        let holder = NSMenuItem(title: "帮助", action: nil, keyEquivalent: "")
        holder.submenu = menu
        return holder
    }

    // MARK: - 工厂

    private static func item(
        _ title: String,
        _ action: Selector?,
        _ key: String,
        modifiers: NSEvent.ModifierFlags = [.command],
        target: AnyObject
    ) -> NSMenuItem {
        let menuItem = NSMenuItem(title: title, action: action, keyEquivalent: key)
        menuItem.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        menuItem.target = target
        return menuItem
    }
}
