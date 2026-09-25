import AppKit
import UniformTypeIdentifiers

/// 主窗口：三栏 + 底部状态栏，并充当各栏之间的协调者。
///
/// 分栏职责被刻意切得很干净 —— 第 1 栏只回答"哪个项目"，第 2 栏只回答"哪个文件"，
/// 第 3 栏只回答"怎么看"。三者之间没有重复入口，因此每个动作的执行路径都是唯一的，
/// 不需要在两处之间同步状态。
final class MainWindowController: NSWindowController {

    private let rootViewController = RootViewController()
    private let projectsViewController = ProjectsViewController()
    private let fileTreeViewController = FileTreeViewController()
    // 不能叫 contentViewController：NSWindowController 已经有这个属性，
    // 同名的协变覆盖是不允许的
    private let contentPane = ContentViewController()

    private var currentFileURL: URL?
    private var isDirty = false

    private var theme = MarkdownTheme()
    private var renderWorkItem: DispatchWorkItem?
    private var fileWatcher: FileWatcher?
    /// 当前文件的类型。非文本文件不允许编辑，也不允许保存 ——
    /// 否则打开一个 .ipa 之后敲几个字按 ⌘S，就会把文本写进那个二进制文件。
    private var currentKind: FileKind?
    /// 上次从磁盘读取（或写入）时该文件的修改时间。
    /// 保存前拿它和磁盘现状比一次，避免静默覆盖别人在外面做的修改。
    private var loadedModificationDate: Date?
    /// 读入时实际使用的编码。保存写回同一种 —— 不能把 GBK 文件悄悄转成 UTF-8
    private var loadedEncoding: String.Encoding = .utf8
    /// 本次打开要恢复到的阅读位置。渲染是异步的，所以先存着，等 performRender 时用掉
    private var pendingScrollFraction: CGFloat?
    /// 渐进渲染填充的代际：每次新打开/新渲染都 +1，过期的填充切片落地前自动放弃
    private var progressiveGeneration = 0
    /// 状态栏上次更新的输入指纹。字数统计是 O(文档长度)，而 refreshChrome 在打开
    /// 路径上会被连调三次（init / 恢复 / 渲染回调）—— 输入没变就整个跳过。
    private var lastStatusFingerprint: Int?
    private var workspaceWatcher: FileWatcher?
    /// openFileFromOutside 带动的项目切换，本次激活不许恢复该项目上次的文件 ——
    /// 用户点的是指定的这个文件，先恢复旧的等于白付一次完整打开（读+渲染+关旧），
    /// 脏文件时还会多弹一次确认框（E-2）。通知是同步发的，激活前立起、处理器里吃掉。
    private var suppressNextWorkspaceRestore = false

    /// 单文件模式：从外面打开的落单文件（不属于任何项目）不开项目，
    /// 两栏收起直接读；打开/切回项目时在 activeWorkspaceChanged 里退出
    private var singleFileMode = false


    /// 用户偏好。设置面板改它，窗口控制器把它应用到排版和编辑器上。
    private var settings = SettingsStore.load()
    private var displaySettingsPopover: NSPopover?
    private var systemSettingsPopover: NSPopover?

    /// 用户选定的呈现方式。它是一份"偏好"而不是"当前文件的状态"：
    /// 切换文件时沿用，只有非文本文件（图片、PDF）才临时改用 Read。
    private var preferredMode: ContentViewController.Mode = .read
    private let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter
    }()

    /// 渐进渲染与打字去抖的四个参数（原先是散在四处注释里的裸数字，
    /// 改一个要同步两处文字 —— 审计 M 类魔法数）
    private enum RenderTuning {
        /// 打字时预览重排的去抖窗口：输入永远优先
        static let typingDebounce: TimeInterval = 0.11
        /// 超过这个字符数的 Markdown 打开时走渐进渲染
        static let progressiveThreshold = 100_000
        /// 渐进渲染首屏的顶层块数（TTFR 的 R 在这里）
        static let firstScreenBlocks = 80
        /// 渐进填充每片最多占主线程的时间，片间让出滚动和输入
        static let fillSliceBudget: TimeInterval = 0.04
        /// 用户滚到已渲染末尾附近时的追赶片预算：他正盯着底部等，输入让路
        static let fillCatchUpBudget: TimeInterval = 0.15
    }

    // MARK: - 初始化

    init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: MuMDesign.defaultWindowContentSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "MuM"
        // 内容延伸到标题栏底下，标题栏本身透明且不显示标题。
        // 这样红绿灯之下直接就是三个面板的底色和各自的头栏，不会出现"标题栏 + 面板头"
        // 两层叠在一起的分裂感。各栏顶栏通过 MuMDesign.windowTopInset 给红绿灯让位。
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.tabbingMode = .disallowed

        super.init(window: window)

        // 关窗要过未保存确认 —— 红灯/⌘W 走 windowShouldClose，⌘Q 走
        // AppDelegate 的 applicationShouldTerminate，两边汇到同一个 confirmDiscardIfNeeded
        window.delegate = self

        // 拖文件/文件夹进窗口 = 打开。根视图是拖拽落点（NSWindow 的拖拽方法
        // 是协议扩展实现，子类重写不到），这里只负责把 URL 接进来。
        rootViewController.onDropURLs = { [weak self] urls in
            self?.openDropped(urls)
        }

        // 启动时的呈现方式来自系统设置。会话内切换只留在内存里 ——
        // 那是"这一次想怎么看"，不该覆盖用户设的启动偏好。
        preferredMode = ContentViewController.Mode(rawValue: settings.startMode.rawValue) ?? .read
        contentPane.mode = preferredMode

        LaunchTimer.mark("  窗口对象已建，开始 buildLayout")
        buildLayout()
        LaunchTimer.mark("  buildLayout 完成")

        // 尺寸相关的设置放在 buildLayout（赋值 contentViewController）之后：
        // AppKit 一拿到内容视图控制器就会用它的 fitting size 反推窗口尺寸。
        window.minSize = NSSize(
            width: MuMDesign.minWindowContentWidth,
            height: MuMDesign.minWindowContentHeight
        )

        applySettings(settings, persist: false)
        LaunchTimer.mark("  applySettings 完成")
        wireCallbacks()
        observeWorkspace()

        // 注意：内容恢复（读文件 + 渲染）不在这里做 —— 窗口先上屏，内容随后。
        // 由 AppDelegate 在 showWindow 之后调 restoreActiveWorkspace。
        refreshChrome()
    }

    /// 启动时的内容恢复（文件监听 + 上次的阅读位置）。
    ///
    /// 故意不在 init 里做：打开体验的第一笔画是窗口框架，不是文件内容 ——
    /// cc 实测 showWindow 会被 init 里 1MB 文件的加载从 ~210ms 拖到 ~368ms。
    /// - Parameter skippingFileRestore: 有外部打开请求（双击 / Dock 拖入）时传 true ——
    ///   用户点的是那个文件，别先为上次会话的遗留文件白付一次加载和渲染。
    func restoreActiveWorkspace(skippingFileRestore: Bool = false) {
        LaunchTimer.mark("  开始 applyWorkspace（读文件 + 渲染）")
        applyWorkspace(WorkspaceStore.shared.active, restoresFile: !skippingFileRestore)
        LaunchTimer.mark("  applyWorkspace 完成")
        refreshChrome()
    }

    /// 首次显示时恢复/设定窗口尺寸。
    ///
    /// 放在 `showWindow` 而不是 `init` 里，是因为 AppKit 会在窗口上屏过程中再做一次
    /// 布局，那时算出来的 fitting size 会覆盖 init 里设过的尺寸。上屏之后再设才作数。
    /// 首次显示时恢复用户上次的窗口尺寸。
    ///
    /// 默认尺寸不在这里设 —— 它由 `RootView` 里的 `.defaultHigh` 约束提供。原因见那里的注释：
    /// AppKit 每个显示周期都会按约束系统重算窗口尺寸，事后 `setFrame` 一定会被覆盖。
    ///
    /// 也没用 NSWindow 自带的 frame autosave：`setFrameUsingName` 在没有保存记录时同样
    /// 返回 `true`，拿它当条件判断不出"有没有历史记录"。
    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        guard let window, !hasSetupWindow else { return }
        hasSetupWindow = true

        window.minSize = NSSize(
            width: MuMDesign.minWindowContentWidth,
            height: MuMDesign.minWindowContentHeight
        )

        if let stored = UserDefaults.standard.string(forKey: Self.windowFrameKey) {
            let rect = NSRectFromString(stored)
            if rect.width >= 480, rect.height >= 360, isOnAnyScreen(rect) {
                window.setFrame(rect, display: true)
            }
        } else {
            // 没存过尺寸 → 用默认值。
            // 必须显式设：RootViewController 现在只提供"最小"约束，
            // 不再有"理想尺寸"，不设的话新装会开在最小值上。
            window.setContentSize(MuMDesign.defaultWindowContentSize)
        }

        // 等首次上屏那轮布局过去之后再开始记录，避免把中间态尺寸存下来
        DispatchQueue.main.async { [weak self] in
            self?.startRecordingWindowFrame(window)
        }
    }

    private func isOnAnyScreen(_ rect: NSRect) -> Bool {
        NSScreen.screens.contains { $0.visibleFrame.intersects(rect) }
    }

    private func startRecordingWindowFrame(_ window: NSWindow) {
        for name in [NSWindow.didResizeNotification, NSWindow.didMoveNotification] {
            NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { note in
                guard let window = note.object as? NSWindow else { return }
                let rect = window.frame
                // 只记录可用尺寸，避免把退化状态写进偏好设置
                guard rect.width >= 480, rect.height >= 360 else { return }
                UserDefaults.standard.set(NSStringFromRect(rect), forKey: Self.windowFrameKey)
            }
        }
    }

    private var hasSetupWindow = false

    private static let windowFrameKey = "MuM.windowFrame"

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - 布局

    private func buildLayout() {
        installPaneBackground(MuMDesign.paneBackground, in: projectsViewController)
        installPaneBackground(MuMDesign.paneBackground, in: fileTreeViewController)
        installPaneBackground(.textBackgroundColor, in: contentPane)

        // 用 contentViewController 而不是裸 contentView：AppKit 会负责把根视图钉满窗口。
        // 窗口尺寸由 RootViewController 里的 .defaultHigh 约束决定。
        window?.contentViewController = rootViewController

        rootViewController.install(
            panes: [projectsViewController.view, fileTreeViewController.view, contentPane.view],
            minimumWidths: [
                MuMDesign.projectsPaneMinWidth,
                MuMDesign.treePaneMinWidth,
                MuMDesign.contentPaneMinWidth,
            ],
            maximumWidths: [
                MuMDesign.projectsPaneMaxWidth,
                MuMDesign.treePaneMaxWidth,
                .greatestFiniteMagnitude,
            ]
        )

        refreshPaneChrome()
    }

    /// 在面板最底层垫一层底色。用独立视图而不是直接给面板 view 上色，
    /// 是为了让它自动跟随明暗模式重绘（PaneBackgroundView 负责这件事）。
    private func installPaneBackground(_ color: NSColor, in controller: NSViewController) {
        let background = PaneBackgroundView(color: color)
        background.translatesAutoresizingMaskIntoConstraints = false
        controller.view.addSubview(background, positioned: .below, relativeTo: nil)
        NSLayoutConstraint.activate([
            background.leadingAnchor.constraint(equalTo: controller.view.leadingAnchor),
            background.trailingAnchor.constraint(equalTo: controller.view.trailingAnchor),
            background.topAnchor.constraint(equalTo: controller.view.topAnchor),
            background.bottomAnchor.constraint(equalTo: controller.view.bottomAnchor),
        ])
    }

    private func wireCallbacks() {
        projectsViewController.onSelect = { index in
            WorkspaceStore.shared.activateShortcut(index)
        }
        projectsViewController.onClose = { index in
            WorkspaceStore.shared.close(index: index)
        }
        projectsViewController.onReveal = { index in
            guard WorkspaceStore.shared.workspaces.indices.contains(index) else { return }
            ExternalOpener.reveal([WorkspaceStore.shared.workspaces[index].rootURL])
        }
        projectsViewController.onAdd = {
            WorkspaceStore.shared.promptForFolder()
        }

        fileTreeViewController.onSelectFile = { [weak self] node in
            self?.open(url: node.url)
        }

        // 布局开关组是折叠的唯一入口：每个面板头里再放一套就地按钮，
        // 就变成同一件事的两个入口了。收起和展开都走左上/右上那一组图标。
        rootViewController.statusBar.layoutCluster.onToggleProjects = { [weak self] in
            self?.toggleProjects()
        }
        rootViewController.statusBar.layoutCluster.onToggleTree = { [weak self] in
            self?.toggleFileTree()
        }

        contentPane.onModeChanged = { [weak self] mode in
            guard let self else { return }
            // 切文件时保持当前呈现方式，不再每次都跳回 Read ——
            // 在 Write 里连着改几个文件时，每次切换都被拽回 Read 是很烦的。
            self.preferredMode = mode
            // 切到 Read / Preview 时必须补一次重排。performRender() 在 Write 模式下会
            // 提前返回，所以预览里留着的可能还是上一个文件的内容（点了 A、又点 B，
            // 一直停在 Write，切到 Read 看到的就是 A）—— 模式切换本身不会重新渲染。
            self.renderPreview(immediately: true)
            self.refreshChrome()
        }
        contentPane.onOpenExternally = { [weak self] in
            guard let url = self?.currentFileURL else { return }
            ExternalOpener.open(url)
        }

        rootViewController.statusBar.onShowDisplaySettings = { [weak self] anchor in
            self?.showDisplaySettings(from: anchor)
        }
        rootViewController.statusBar.onShowSettings = { [weak self] anchor in
            self?.showSystemSettings(from: anchor)
        }

        // 内容区右上 ···：导出菜单（无文档 / 非文本时置灰，见 NSMenuItemValidation 扩展）
        contentPane.exportButton.menu = makeExportMenu()

        // 文件树的文件管理动作：新建文件/文件夹与重命名落盘都在窗口控制器 ——
        // 它要跟打开状态（重命名打开中的文件，路径要跟到新 URL）
        fileTreeViewController.onNewFileRequest = { [weak self] in
            self?.newDocument()
        }
        fileTreeViewController.onNewFolderRequest = { [weak self] in
            self?.newFolder()
        }
        fileTreeViewController.onRenameNode = { [weak self] node, newName in
            self?.performRename(node: node, newName: newName) ?? false
        }
        fileTreeViewController.onTrashNode = { [weak self] node in
            self?.trashNode(node)
        }

        let editor = contentPane.editorViewController
        editor.onTextChanged = { [weak self] _ in
            self?.markDirty()
        }
        editor.onScroll = { [weak self] fraction in
            guard let self, self.contentPane.isSideBySide else { return }
            // 按内容联动：视口顶源码行 → 预览渲染位置（锚点不全时内部退回比例）
            let editor = self.contentPane.editorViewController
            self.contentPane.previewViewController.scrollToSourceLine(
                editor.topVisibleSourceLine(),
                sourceLineCount: editor.sourceLineCount,
                fallbackFraction: fraction
            )
        }

        contentPane.previewViewController.onOpenInternalLink = { [weak self] url in
            guard let self else { return false }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else { return false }
            self.open(url: url)
            return true
        }

        // 大纲栏：点击跳转；预览滚动时跟随高亮「当前节」
        contentPane.tocController.onSelect = { [weak self] location in
            self?.contentPane.previewViewController.revealRenderedOffset(location)
        }
        // 竖线左侧「›」收成窄条；窄条「‹」拉回、「×」彻底关
        contentPane.onTOCCollapse = { [weak self] in self?.setTOCState(.rail) }
        contentPane.onTOCExpand = { [weak self] in self?.setTOCState(.open) }
        contentPane.onTOCClose = { [weak self] in self?.setTOCState(.closed) }
        contentPane.previewViewController.onScrollPosition = { [weak self] in
            guard let self, self.tocState == .open, self.contentPane.mode != .write else { return }
            self.contentPane.tocController.setCurrentLocation(
                self.contentPane.previewViewController.topVisibleRenderedOffset()
            )
        }
        applyTOCVisibility()

        contentPane.previewViewController.onGlobalSearchSelection = { [weak self] query in
            self?.showGlobalSearch(prefill: query)
        }
    }

    private func observeWorkspace() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(activeWorkspaceChanged),
            name: .mumActiveWorkspaceChanged,
            object: nil
        )
    }

    // MARK: - 项目

    @objc private func activeWorkspaceChanged() {
        // 吃掉标记要在脏检查之前：标记只对这一次通知有效，取消路径也不能留到下次
        let restoresFile = !suppressNextWorkspaceRestore
        suppressNextWorkspaceRestore = false
        // 项目回来了就退出单文件模式：两栏还原
        if singleFileMode {
            singleFileMode = false
            setPane(0, collapsed: false)
            setPane(1, collapsed: false)
        }
        if isDirty, !confirmDiscardIfNeeded() { return }
        closeCurrentFile()
        applyWorkspace(WorkspaceStore.shared.active, restoresFile: restoresFile)
        refreshChrome()
    }

    private func applyWorkspace(_ workspace: Workspace?, restoresFile: Bool = true) {
        workspaceWatcher?.stop()
        workspaceWatcher = nil

        guard let workspace else { return }

        // 递归监听项目根：文件增删改都会刷新文件树
        let watcher = FileWatcher(path: workspace.rootURL.path) {
            workspace.root.invalidate()
            NotificationCenter.default.post(name: .mumFileTreeChanged, object: nil)
        }
        watcher.start()
        workspaceWatcher = watcher

        if restoresFile {
            restoreReadingPosition(for: workspace)
        }
    }

    /// 切回一个项目时回到上次在读的那一篇；没有记录就退而求其次打开 README。
    /// 空白界面对于「切过去看一眼」的场景是纯粹的浪费。
    private func restoreReadingPosition(for workspace: Workspace) {
        guard settings.restoresLastSession else {
            // 关掉恢复时，退回该项目里的第一个 README，保持"打开就有东西看"
            if let readme = firstReadme(in: workspace) {
                open(url: readme)
            }
            return
        }

        if let last = WorkspaceStore.shared.lastOpenedFile(for: workspace) {
            open(url: last)
            if currentFileURL != nil { return }
        }

        if let readme = firstReadme(in: workspace) {
            open(url: readme)
        }
    }

    private func firstReadme(in workspace: Workspace) -> URL? {
        let files = workspace.root.loadChildren().filter { !$0.isDirectory }
        for candidate in ["readme.md", "readme.markdown", "index.md", "readme"] {
            if let match = files.first(where: { $0.name.lowercased() == candidate }) {
                return match.url
            }
        }
        return nil
    }

    // MARK: - 打开文件

    /// 从访达 / `open` 命令打开单个文件。
    ///
    /// 属于已打开的项目 → 切过去；**不属于 → 单文件模式**：不把所在文件夹
    /// 开成项目（那会把整个文件夹的内容请进文件树，对「双击读一份文件」太重），
    /// 两栏收起、内容区直接读。打开或切回项目时自动退出（activeWorkspaceChanged）。
    func openFileFromOutside(_ url: URL) {
        let file = url.standardizedFileURL
        let store = WorkspaceStore.shared

        if let index = store.workspaces.firstIndex(where: {
            file.path.hasPrefix($0.rootURL.path + "/")
        }) {
            // 只有真的触发切换通知才立标记（同项目 activate 是 no-op，
            // 立了会留下来吃掉下一次正经的恢复）
            if index != store.activeIndex { suppressNextWorkspaceRestore = true }
            store.activate(index: index)
        } else {
            singleFileMode = true
            setPane(0, collapsed: true)
            setPane(1, collapsed: true)
        }

        open(url: file)
    }

    /// 外部打开的统一入口（双击 / `open -a` / Dock 拖入 / 窗口拖入）：
    /// 文件夹开成项目，文件走 openFileFromOutside（它会处理「不属于任何项目」的情况）。
    func openIncoming(_ url: URL) {
        LaunchTimer.mark("openIncoming: \(url.lastPathComponent)")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) else { return }

        if isDirectory.boolValue {
            WorkspaceStore.shared.open(url: url)
        } else {
            // Info.plist 里声明了 Markdown 文档类型，双击 .md 也得能打开
            openFileFromOutside(url)
        }
    }

    /// 拖进窗口的打开：窗口已经接住拖拽了，人也看着这个窗口，补上激活就到前台
    private func openDropped(_ urls: [URL]) {
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        for url in urls {
            openIncoming(url)
        }
    }

    func open(url: URL, recordingHistory: Bool = true) {
        let standardized = url.standardizedFileURL
        guard standardized != currentFileURL else { return }
        guard confirmDiscardIfNeeded() else { return }

        // 浏览器范式：从 A 走到 B，A 进后退栈，前进栈清空。
        // 所有打开路径都记 —— 不管从文件树、⌘P、全局搜索还是文档链接进来，
        // "回去"的语义应该一致
        if recordingHistory, let current = currentFileURL {
            backStack.append(current)
            if backStack.count > 100 { backStack.removeFirst() }
            forwardStack.removeAll()
        }

        // 换文件：上一份文档可能还在渐进填充，让它作废
        progressiveGeneration += 1
        saveReadingPosition()
        closeCurrentFile()

        let kind = FileKind(url: standardized, isDirectory: false)

        switch kind {
        case .markdown, .code, .plainText:
            loadTextFile(url: standardized, kind: kind)

        case .image:
            contentPane.previewViewController.show(image: NSImage(contentsOf: standardized) ?? NSImage())
            currentFileURL = standardized
            contentPane.editorViewController.setEditable(false)

        case .pdf:
            contentPane.previewViewController.show(pdf: standardized)
            currentFileURL = standardized
            contentPane.editorViewController.setEditable(false)

        case .richText:
            loadRichTextFile(url: standardized)

        case .unsupported:
            contentPane.previewViewController.showUnsupported(url: standardized)
            currentFileURL = standardized
            contentPane.editorViewController.setEditable(false)

        case .folder:
            contentPane.previewViewController.showMessage(
                symbol: "questionmark.folder",
                title: standardized.lastPathComponent,
                subtitle: "这个格式暂时不支持预览"
            )
            currentFileURL = standardized
            contentPane.editorViewController.setEditable(false)
        }

        currentKind = kind

        // 文本文件沿用用户选的呈现方式；图片 / PDF 没有"编辑"可言，临时用 Read。
        // 注意这里不改 preferredMode —— 看完一张图再切回 Markdown，应该还是原来的模式。
        contentPane.mode = kind.isTextual ? preferredMode : .read
        contentPane.setModeControlTextual(kind.isTextual)

        // 非 Markdown 文件才提供"用默认应用打开"：MuM 给出源码，
        // 渲染结果（HTML 页面、SVG 图形、PDF…）交给系统。自己实现 HTML 渲染
        // 要么引入 Web 引擎（毁掉护城河），要么永远追不上浏览器。
        updateExternalOpenButton(for: standardized, kind: kind)

        fileTreeViewController.reveal(url: standardized)
        startFileWatcher(for: standardized)

        if let workspace = WorkspaceStore.shared.active {
            WorkspaceStore.shared.rememberOpenedFile(standardized, in: workspace)
        }

        refreshChrome()
    }

    /// 「用默认应用打开」的显隐与提示文案。
    /// 文案里带上具体应用名（"用 Safari 打开"），比"用默认应用打开"明确得多。
    private func updateExternalOpenButton(for url: URL, kind: FileKind) {
        let available = kind != .markdown
        guard available else {
            contentPane.setExternalOpenAvailable(false, tooltip: nil)
            return
        }

        let appName = NSWorkspace.shared
            .urlForApplication(toOpen: url)
            .map { FileManager.default.displayName(atPath: $0.path) }
        contentPane.setExternalOpenAvailable(
            true,
            tooltip: appName.map { "用 \($0) 打开" } ?? "用默认应用打开"
        )
    }

    /// RTF：NSAttributedString 原生渲染，只读。
    /// 不进编辑器 —— 编辑后保存会把纯文本盖在 RTF 控制字上（见 FileKind.richText）。
    private func loadRichTextFile(url: URL) {
        let options: [NSAttributedString.DocumentReadingOptionKey: Any] = [
            .documentType: NSAttributedString.DocumentType.rtf
        ]
        guard let attributed = try? NSAttributedString(
            url: url, options: options, documentAttributes: nil
        ) else {
            contentPane.previewViewController.showMessage(
                symbol: "exclamationmark.triangle",
                title: "无法读取",
                subtitle: url.lastPathComponent
            )
            contentPane.editorViewController.setText("")
            contentPane.editorViewController.setEditable(false)
            currentFileURL = url
            contentPane.mode = .read
            return
        }
        contentPane.previewViewController.show(attributed: attributed, restoreFraction: nil)
        currentFileURL = url
        contentPane.editorViewController.setEditable(false)
    }

    private func loadTextFile(url: URL, kind: FileKind) {
        // 先取 mtime 再读内容（顺序不能反）：读取中途文件被改的话，
        // 基线必须落在改动之前，⌘S 的冲突检测才兜得住（审计 D-6）
        let mtime = try? FileManager.default
            .attributesOfItem(atPath: url.path)[.modificationDate] as? Date

        guard let decoded = TextDecoding.decode(url: url) else {
            // 读不了或判定为二进制：进安全空状态，编辑器必须不可编辑 ——
            // 否则对着空编辑器敲字再 ⌘S，会把文本盖到读不出来的原文件上（审计 D-8）
            contentPane.previewViewController.showMessage(
                symbol: "exclamationmark.triangle",
                title: "无法以文本读取",
                subtitle: url.lastPathComponent
            )
            contentPane.editorViewController.setText("")
            contentPane.editorViewController.setEditable(false)
            currentFileURL = url
            contentPane.mode = .read
            return
        }

        currentFileURL = url
        isDirty = false
        loadedModificationDate = mtime
        loadedEncoding = decoded.encoding
        LaunchTimer.mark("    readText 完成")
        contentPane.editorViewController.setEditable(true)
        contentPane.editorViewController.setText(decoded.text)
        LaunchTimer.mark("    编辑器 setText 完成")
        // 换文件必须给出一个显式落点：没保存过位置就回顶（0）。
        // 传 nil 会被 show() 当成「同一文件重排」而保持原滚动位 —— 上一个是长文档时，
        // 短文档会落在越界位置，读完一屏空白（ice 2026-09-25 实测撞见）。
        pendingScrollFraction = WorkspaceStore.shared.readingPosition(for: url).map { CGFloat($0) } ?? 0
        renderPreview(immediately: true, allowProgressive: true)
    }

    // MARK: - 渲染预览

    private func markDirty() {
        if !isDirty {
            isDirty = true
            refreshChrome()
        }
        renderPreview(immediately: false)
    }

    /// - Parameter allowProgressive: 只有「打开文件」这条路径该传 true。
    ///   打字重排和模式切换要精确保留滚动位置，走同步渲染。
    private func renderPreview(immediately: Bool, allowProgressive: Bool = false) {
        renderWorkItem?.cancel()

        // 预览重排和状态栏的字数统计都放进同一个去抖窗口：
        // 两者都是 O(文档长度)，没必要每个按键都跑一遍
        let work = DispatchWorkItem { [weak self] in
            self?.performRender(allowProgressive: allowProgressive)
            self?.updateStatusBar()
        }
        renderWorkItem = work

        if immediately {
            // 打开路径同步跑：异步会让渲染排到窗口首帧之后（实测被挤掉 ≈127ms），
            // 而 TTFR 的 R 就是这一次渲染 —— 它等不得。反正总阻塞时长一样，
            // 同步只是把它从"一个 runloop 之后"挪到"现在"。
            work.perform()
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + RenderTuning.typingDebounce, execute: work)
        }
    }

    private func performRender(allowProgressive: Bool = false) {
        // 任何一次新渲染都让进行中的渐进填充作废
        progressiveGeneration += 1

        guard let url = currentFileURL else { return }
        guard contentPane.mode != .write else { return }
        guard FileKind(url: url, isDirectory: false).isTextual else { return }

        LaunchTimer.mark("    performRender 开始（异步渲染）")
        contentPane.previewViewController.previewTextView.maxContentWidth = theme.maxContentWidth

        let renderer = MarkdownRenderer(theme: theme, baseURL: url.deletingLastPathComponent())
        let text = contentPane.editorViewController.text
        let kind = FileKind(url: url, isDirectory: false)

        let restore = pendingScrollFraction
        pendingScrollFraction = nil

        // 渐进渲染：大文档打开时先渲染首屏顶层块立刻上屏（TTFR 的 R 在这里），
        // 余量切薄片分次补齐，填充期间滚动保持可用。
        // 回滚开关：defaults write sh.ice.mum MuM.disableProgressiveRender -bool true
        // （bench 包是 sh.ice.mum.bench）。只改时机不改内容 —— 拼接结果与全量渲染逐字一致。
        if allowProgressive, !forceFullRenderForNextOpen, case .markdown = kind,
           text.count > RenderTuning.progressiveThreshold,
           !UserDefaults.standard.bool(forKey: "MuM.disableProgressiveRender") {
            renderProgressively(renderer: renderer, text: text, restore: restore)
            return
        }

        let attributed: NSAttributedString
        switch kind {
        case .markdown:
            attributed = renderer.render(text)
            contentPane.previewViewController.setOutline(renderer.outline)
            contentPane.tocController.setOutline(renderer.outline)
            contentPane.previewViewController.setBlockAnchors(renderer.blockAnchors, complete: true)
        case .code:
            attributed = renderer.renderCode(text, language: FileKind.language(for: url))
            contentPane.previewViewController.setBlockAnchors([], complete: false)
        case .plainText:
            // csv / tsv 按表格渲染 —— 表格排版是手工调过的，阅读优先；
            // 解析失败（空文件、单列、超行数上限）退回纯文本，内容完整可见
            if let delimiter = FileKind.tableDelimiter(for: url),
               let table = DelimitedTable.markdown(from: text, delimiter: delimiter) {
                attributed = renderer.render(table)
                contentPane.previewViewController.setOutline([])
                contentPane.tocController.setOutline([])
                // csv 是从纯文本折算的 Markdown，块锚点的源码行对不上原文 —— 退回比例
                contentPane.previewViewController.setBlockAnchors([], complete: false)
            } else {
                attributed = renderer.renderPlainText(text)
                contentPane.previewViewController.setBlockAnchors([], complete: false)
            }
        default:
            attributed = renderer.renderPlainText(text)
            contentPane.previewViewController.setBlockAnchors([], complete: false)
        }
        LaunchTimer.mark("    render 返回（AST→富文本）")

        contentPane.previewViewController.show(attributed: attributed, restoreFraction: restore)
        contentPane.previewViewController.setEndMarker(.done)
        LaunchTimer.mark("    预览已写入富文本")
    }

    /// 渐进渲染的填充循环：每片有时间预算，片间让出主线程处理滚动和输入。
    /// 代际不匹配（用户打开了别的文件 / 触发了新渲染）就悄悄停下。
    private func renderProgressively(renderer: MarkdownRenderer, text: String, restore: CGFloat?) {
        let session = ProgressiveRenderSession(renderer: renderer, markdown: text)
        let first = session.renderFirst(count: RenderTuning.firstScreenBlocks)
        // 新文档一律从顶部开始；保存的阅读位置等全文补齐后再还 ——
        // 填充到一半时全文高度还是错的，按比例恢复会落错地方
        contentPane.previewViewController.setBlockAnchors(session.blockAnchors, complete: session.isFinished)
        contentPane.previewViewController.show(attributed: first, restoreFraction: 0)
        contentPane.previewViewController.setEndMarker(session.isFinished ? .done : .loading)
        LaunchTimer.mark("    渐进：首屏已写入（TTFR 的 R）")
        fillProgressively(session: session, generation: progressiveGeneration, restore: restore)
    }

    private func fillProgressively(session: ProgressiveRenderSession, generation: Int, restore: CGFloat?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, generation == self.progressiveGeneration else { return }
            // 用户滚到已渲染末尾附近就加速追赶 —— 他正盯着底部等下一片，
            // 「以为文档结束了」就是这个时刻的错觉
            let budget: TimeInterval = self.contentPane.previewViewController.isNearRenderedEnd
                ? RenderTuning.fillCatchUpBudget
                : RenderTuning.fillSliceBudget
            if let chunk = session.renderNext(timeBudget: budget) {
                self.contentPane.previewViewController.append(attributed: chunk)
                self.contentPane.previewViewController.setBlockAnchors(session.blockAnchors, complete: session.isFinished)
            }
            guard session.isFinished else {
                self.fillProgressively(session: session, generation: generation, restore: restore)
                return
            }
            LaunchTimer.mark("    渐进：全文已补齐")
            self.contentPane.previewViewController.setEndMarker(.done)
            self.contentPane.previewViewController.setOutline(session.outline)
            self.contentPane.tocController.setOutline(session.outline)
            // 填充期间用户没滚动过，才把保存的阅读位置还回去；动过就以用户为准
            if let restore, restore > 0.001,
               self.contentPane.previewViewController.scrollFraction() < 0.001 {
                self.contentPane.previewViewController.restoreScrollFraction(restore)
            }
        }
    }

    // MARK: - 新建文件（⌘N）

    /// ⌘N：快速建一个文件并立刻写内容。三个入口同一动作：
    /// 菜单「文件 → 新建文件」、文件树栏头部 ··· 菜单（响应链到 AppDelegate）。
    ///
    /// 有项目：落在文件树当前选中的目录（选中文件取其父目录，没选中取项目根），
    ///   递增命名 `未命名.md` / `未命名2.md` …，绝不覆盖；建好后打开 + Write 模式 +
    ///   光标进编辑器 —— 这个功能的诉求就是"立刻写"。
    /// 单文件模式：落在当前打开的文件旁边（项目栏收起着呢，建进看不见的项目里
    ///   等于丢了）；没有打开的文件才弹保存面板。
    /// 无项目：保存面板选位置和文件名，建好后走现有的"打开单个文件"路径。
    ///
    /// 返回创建成功的文件 URL（无项目的保存面板是异步的，那种情形返回 nil）。
    @discardableResult
    func newDocument() -> URL? {
        if singleFileMode, let current = currentFileURL {
            guard let candidate = createUntitled(in: current.deletingLastPathComponent()) else {
                return nil
            }
            open(url: candidate)
            guard currentFileURL == candidate.standardizedFileURL else { return nil }
            setMode(.write)
            contentPane.editorViewController.focusEditor()
            return candidate
        }

        guard let workspace = WorkspaceStore.shared.active else {
            presentNewFilePanel()
            return nil
        }

        let selected = fileTreeViewController.selectedNode
        let dir = selected.map { $0.isDirectory ? $0.url : $0.url.deletingLastPathComponent() }
            ?? workspace.rootURL

        guard let candidate = createUntitled(in: dir) else { return nil }

        // 文件树的子节点缓存是落盘前建的，等 FSEvents 的异步刷新会让
        // 紧接着的 reveal 找不到新文件。先失效再重载（重载会重建整层节点），
        // open() 内部的 reveal 就能同步选中它
        workspace.root.invalidate()
        fileTreeViewController.refreshPreservingExpansion()

        open(url: candidate)
        guard currentFileURL == candidate.standardizedFileURL else { return nil }

        // 打开即写：Write 模式 + 光标进编辑器
        setMode(.write)
        contentPane.editorViewController.focusEditor()
        return candidate
    }

    /// 递增命名 `未命名.md` 落盘，绝不覆盖。失败弹错误并返回 nil。
    private func createUntitled(in dir: URL) -> URL? {
        var candidate = dir.appendingPathComponent("未命名.md")
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("未命名\(index).md")
            index += 1
        }

        do {
            // 空文件就好：模板是第二次输入的负担，用户要的是立刻能写。
            // withoutOverwriting 兜底命名竞态（命名检查后落盘前有人建了同名文件）
            try Data().write(to: candidate, options: .withoutOverwriting)
        } catch {
            presentError(message: "新建文件失败", detail: error.localizedDescription)
            return nil
        }
        return candidate
    }

    /// 无项目时的新建：保存面板选位置和名字
    private func presentNewFilePanel() {
        guard let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType("net.daringfireball.markdown") ?? .plainText]
        panel.nameFieldStringValue = "未命名.md"
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, response == .OK, let url = panel.url else { return }
            // 已存在就不覆盖（保存面板已问过用户）：直接打开它；不存在才建空文件
            if !FileManager.default.fileExists(atPath: url.path) {
                do {
                    try Data().write(to: url, options: .withoutOverwriting)
                } catch {
                    presentError(message: "新建文件失败", detail: error.localizedDescription)
                    return
                }
            }
            openFileFromOutside(url)
            guard currentFileURL == url.standardizedFileURL else { return }
            setMode(.write)
            contentPane.editorViewController.focusEditor()
        }
    }

    // MARK: - 新建文件夹 / 重命名
    //
    // 文件管理动作的统一落点：文件树右键菜单、··· 菜单都汇到这里。
    // 命名一律递增不覆盖；落盘失败走 presentError。

    /// 新建文件夹：与新建文件同一套目录推导（选中项的目录 / 项目根）。
    /// 文件夹没有"写内容"，名字就是它的全部 —— 建完直接进行内重命名编辑态。
    @discardableResult
    func newFolder() -> URL? {
        guard let workspace = WorkspaceStore.shared.active else { return nil }

        let selected = fileTreeViewController.selectedNode
        let dir = selected.map { $0.isDirectory ? $0.url : $0.url.deletingLastPathComponent() }
            ?? workspace.rootURL

        var candidate = dir.appendingPathComponent("未命名文件夹")
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = dir.appendingPathComponent("未命名文件夹\(index)")
            index += 1
        }

        do {
            try FileManager.default.createDirectory(at: candidate, withIntermediateDirectories: false)
        } catch {
            presentError(message: "新建文件夹失败", detail: error.localizedDescription)
            return nil
        }

        // 与新建文件同理：树的缓存是落盘前的，先失效重载，编辑态才找得到新节点
        workspace.root.invalidate()
        fileTreeViewController.refreshPreservingExpansion()
        fileTreeViewController.beginRename(url: candidate)
        return candidate
    }

    /// 行内重命名的校验。返回 nil = 可以改；提成独立方法让测试直接断言校验规则
    func renameValidationError(node: FileNode, newName: String) -> String? {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return "名字不能为空" }
        if trimmed.contains("/") { return "名字不能包含「/」" }
        guard trimmed != node.name else { return nil }
        let target = node.url.deletingLastPathComponent().appendingPathComponent(trimmed)
        if FileManager.default.fileExists(atPath: target.path) { return "「\(trimmed)」已存在" }
        return nil
    }

    /// 行内重命名的落盘与状态跟随。返回是否成功；失败时按 presentErrors 决定要不要
    /// 弹错误框（测试进程里弹模态框会永远等不到点击，--uitest 传 false 走静默断言）
    @discardableResult
    func performRename(node: FileNode, newName: String, presentErrors: Bool = true) -> Bool {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        // 没改名 = 直接算成功（等于用户看了看又放弃了）
        guard trimmed != node.name else { return true }
        if let message = renameValidationError(node: node, newName: trimmed) {
            if presentErrors { presentError(message: "重命名失败", detail: message) }
            return false
        }

        let oldURL = node.url
        let target = oldURL.deletingLastPathComponent().appendingPathComponent(trimmed)
        do {
            // moveItem 不覆盖已存在的目标（校验已挡过，这里是第二道）
            try FileManager.default.moveItem(at: oldURL, to: target)
        } catch {
            if presentErrors { presentError(message: "重命名失败", detail: error.localizedDescription) }
            return false
        }

        followRenamedNode(from: oldURL, to: target, isDirectory: node.isDirectory)

        // 树刷新并选中新位置
        WorkspaceStore.shared.active?.root.invalidate()
        fileTreeViewController.refreshPreservingExpansion()
        fileTreeViewController.reveal(url: target)
        return true
    }

    /// 重命名/移动后，打开状态跟到新 URL。不换的话，⌘S 会写回旧位置 ——
    /// 等于在旧路径复制出一个幽灵文件，未保存的改动看起来"丢了"。
    /// 文件夹被改名时，打开中的文件在它里面的，路径同样要跟。
    private func followRenamedNode(from oldURL: URL, to newURL: URL, isDirectory: Bool) {
        guard let current = currentFileURL else { return }

        // 比较走 realPath：树节点路径已解链接，currentFileURL 可能没解（/var vs /private/var）
        let currentPath = current.realPath
        let oldPath = oldURL.realPath
        let newCurrent: URL?
        if currentPath == oldPath {
            newCurrent = newURL
        } else if isDirectory, currentPath.hasPrefix(oldPath + "/") {
            let suffix = String(currentPath.dropFirst(oldPath.count + 1))
            newCurrent = newURL.appendingPathComponent(suffix)
        } else {
            newCurrent = nil
        }
        guard let newCurrent else { return }

        currentFileURL = newCurrent
        // 文件监听跟着走，不然外部再改动就监听不到了
        startFileWatcher(for: newCurrent)
        if let workspace = WorkspaceStore.shared.active {
            WorkspaceStore.shared.rememberOpenedFile(newCurrent, in: workspace)
        }
        refreshChrome() // 窗口标题、状态栏位置
    }

    // MARK: - 删除（移到废纸篓）

    /// 移到废纸篓 —— 可恢复，绝不做彻底删除（ice 2026-09-19 拍的：需要删除，
    /// 但跳访达太麻烦；废纸篓就是后悔药）。打开中的文件被删前先收尾：
    /// 脏检查走 confirmDiscardIfNeeded（用户可取消），然后关文档；
    /// 删目录时打开中的文件在它里面同样收尾。返回是否成功。
    @discardableResult
    func trashNode(_ node: FileNode, presentErrors: Bool = true) -> Bool {
        let url = node.url
        if let current = currentFileURL {
            let currentPath = current.realPath
            let targetPath = url.realPath
            if currentPath == targetPath || (node.isDirectory && currentPath.hasPrefix(targetPath + "/")) {
                if isDirty, !confirmDiscardIfNeeded() { return false }
                closeCurrentFile()
                refreshChrome()
            }
        }
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
        } catch {
            if presentErrors { presentError(message: "移到废纸篓失败", detail: error.localizedDescription) }
            return false
        }
        WorkspaceStore.shared.active?.root.invalidate()
        fileTreeViewController.refreshPreservingExpansion()
        return true
    }

    // MARK: - 导出（⌘⇧E）

    /// 当前文档可导出：有打开的文本文件（图片 / PDF 没有"导出渲染结果"这回事）
    var canExport: Bool { hasOpenDocument && (currentKind?.isTextual ?? false) }

    /// ⌘⇧E：导出当前文档的渲染结果。保存面板只管"存到哪、什么格式"，
    /// 渲染走 DocumentRenderer —— 与 headless `MuM render` 同一个入口。
    func exportDocument() {
        guard let url = currentFileURL else { return }
        presentExportPanel(
            allowedContentTypes: [.png, .pdf],
            defaultName: url.deletingPathExtension().lastPathComponent + ".png"
        )
    }

    /// ··· 菜单的导出：格式由菜单项预选，保存面板只管位置和文件名
    func exportDocument(format: DocumentRenderer.Format) {
        guard let url = currentFileURL else { return }
        presentExportPanel(
            allowedContentTypes: [format.contentType],
            defaultName: url.deletingPathExtension().lastPathComponent + "." + format.pathExtension
        )
    }

    private func presentExportPanel(allowedContentTypes: [UTType], defaultName: String) {
        guard canExport, let window else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = allowedContentTypes
        panel.nameFieldStringValue = defaultName
        panel.beginSheetModal(for: window) { [weak self] response in
            guard response == .OK, let output = panel.url else { return }
            self?.exportRendered(to: output)
        }
    }

    /// 内容区右上 ··· 的菜单：导出两项，格式预选。
    /// 项要短（ice 2026-09-19）：小图标 + PNG / PDF，不写「导出为 PNG…」这种长句。
    private func makeExportMenu() -> NSMenu {
        let menu = NSMenu()
        let png = NSMenuItem(title: "PNG", action: #selector(exportAsPNG(_:)), keyEquivalent: "")
        png.target = self
        png.image = NSImage(systemSymbolName: "photo", accessibilityDescription: nil)
        let pdf = NSMenuItem(title: "PDF", action: #selector(exportAsPDF(_:)), keyEquivalent: "")
        pdf.target = self
        pdf.image = NSImage(systemSymbolName: "doc.richtext", accessibilityDescription: nil)
        menu.addItem(png)
        menu.addItem(pdf)
        return menu
    }

    @objc private func exportAsPNG(_ sender: Any?) { exportDocument(format: .png) }
    @objc private func exportAsPDF(_ sender: Any?) { exportDocument(format: .pdf) }

    /// 面板落定后的实际导出。导出编辑器里的当前内容（含未保存改动）—— 所见即所得。
    private func exportRendered(to output: URL) {
        do {
            try exportRenderedOrThrow(to: output)
        } catch {
            presentError(message: "导出失败", detail: error.localizedDescription)
        }
    }

    /// 诊断用（UITestRunner）：导出到确定性路径，不弹保存面板，成败用返回值说话
    /// （失败时不能走 presentError —— 测试进程里弹模态框会永远等不到点击）
    func debugExport(to output: URL) -> Bool {
        (try? exportRenderedOrThrow(to: output)) != nil
    }

    /// 诊断用（UITestRunner）：··· 菜单本体 —— 断言菜单项存在与置灰逻辑
    var debugExportMenu: NSMenu? { contentPane.exportButton.menu }

    /// 诊断用（UITestRunner）：新建文件的断言点 —— 光标位置与文件树选中
    var debugEditorFocused: Bool { contentPane.editorViewController.debugIsFocused }
    var debugSelectedTreeFile: URL? { fileTreeViewController.selectedNode?.url }

    /// 诊断用（UITestRunner）：文件管理动作 —— 右键菜单与行内重命名的断言点
    var debugSelectedNode: FileNode? { fileTreeViewController.selectedNode }
    var debugTreeMenuTitles: [String] { fileTreeViewController.debugProjectMenuTitles }
    func debugSelectTreeNode(url: URL) { fileTreeViewController.reveal(url: url) }
    func debugRenameSelectedNode() { fileTreeViewController.beginRenameSelected() }
    var debugIsRenaming: Bool { fileTreeViewController.debugIsRenaming }
    var debugRenameFieldActive: Bool { fileTreeViewController.debugRenameFieldActive }
    func debugCommitRename(_ newName: String) { fileTreeViewController.debugCommitRename(newName) }
    func debugCancelRename() { fileTreeViewController.debugCancelRename() }

    /// 导出参数：跟随当前的阅读主题与排版设置；明暗跟随 app 当前外观（dark 留 nil）
    private func exportRenderedOrThrow(to output: URL) throws {
        guard let kind = currentKind else { return }
        var options = DocumentRenderer.Options()
        options.readingTheme = settings.readingTheme
        options.fontSize = settings.previewFontSize
        options.lineSpacing = settings.lineSpacing
        options.blockSpacing = settings.blockSpacing
        options.letterSpacing = settings.letterSpacing
        options.previewFont = settings.previewFont
        options.width = CGFloat(settings.readingWidth.rawValue)
        try DocumentRenderer.write(
            text: contentPane.editorViewController.text,
            kind: kind,
            baseURL: currentFileURL?.deletingLastPathComponent(),
            to: output,
            options: options
        )
    }

    // MARK: - 前进 / 后退

    /// 阅读动线的历史：链接跳转、文件树点击、搜索结果，全都在一条线上。
    /// 不做 tab —— tab 是"同时对照多个文档"的界面，和文件树职责重叠；
    /// "读过想回去"用浏览器范式的前进/后退覆盖，零常驻 chrome
    private var backStack: [URL] = []
    private var forwardStack: [URL] = []

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    func goBack() {
        guard let target = backStack.last else { return }
        let previous = currentFileURL
        backStack.removeLast()
        if let previous { forwardStack.append(previous) }
        open(url: target, recordingHistory: false)
        // 脏文件确认被取消（或打开失败）→ 没走成，把栈还原
        if currentFileURL != target {
            if let previous { forwardStack.removeAll(where: { $0 == previous }) }
            backStack.append(target)
        }
    }

    func goForward() {
        guard let target = forwardStack.last else { return }
        let previous = currentFileURL
        forwardStack.removeLast()
        if let previous { backStack.append(previous) }
        open(url: target, recordingHistory: false)
        if currentFileURL != target {
            if let previous { backStack.removeAll(where: { $0 == previous }) }
            forwardStack.append(target)
        }
    }

    // MARK: - 保存

    var hasOpenDocument: Bool { currentFileURL != nil }

    // MARK: - 查找

    /// 预览里可查找的前提：当前显示的是一个文本文件，且不在纯编辑模式
    var canFindInPreview: Bool {
        (currentKind?.isTextual ?? false) && contentPane.mode != .write
    }

    var isFindingInPreview: Bool {
        contentPane.previewViewController.isFinding
    }

    func showPreviewFind() {
        guard canFindInPreview else { return }
        contentPane.previewViewController.showFindBar()
    }


    func findNext() { contentPane.previewViewController.findNext() }
    func findPrevious() { contentPane.previewViewController.findPrevious() }

    /// 记住当前读到哪。切文件和退出应用时各存一次 ——
    /// 这就够覆盖"关掉再打开落回原位置"，不需要在每次滚动时写 UserDefaults。
    func saveReadingPosition() {
        guard let url = currentFileURL else { return }
        let fraction = contentPane.mode == .write
            ? contentPane.editorViewController.scrollFraction()
            : contentPane.previewViewController.scrollFraction()
        WorkspaceStore.shared.rememberReadingPosition(Double(fraction), for: url)
    }

    /// 诊断用：离屏展开大纲栏（快照 --outline）
    func debugOutline() {
        setTOCState(.open)
    }

    /// 诊断用：离屏触发一次查找
    func debugFind(_ query: String) {
        guard canFindInPreview else { return }
        contentPane.previewViewController.debugRunFind(query)
    }

    /// 诊断用：模拟设置面板在**运行时**改动偏好。
    /// 启动时读设置和运行时改设置是两条路径，前者通不代表后者通。
    func debugApplySettings(_ mutate: (inout MuMSettings) -> Void) {
        var updated = settings
        mutate(&updated)
        applySettings(updated, persist: false)
    }

    // MARK: - 诊断钩子（UITestRunner）
    //
    // 自驱动 UI 测试的观察口：全部只读或仅触发既有动作，不改正常路径行为。

    /// 当前生效的偏好（settings 本身是 private）
    var debugSettings: MuMSettings { settings }

    /// 两个设置 popover：从真实的状态栏按钮触发，走和产品一致的 wiring
    func debugShowDisplaySettings() { rootViewController.statusBar.debugTriggerDisplaySettings() }
    func debugShowSystemSettings() { rootViewController.statusBar.debugTriggerSystemSettings() }
    var debugDisplaySettingsShown: Bool { displaySettingsPopover?.isShown ?? false }
    var debugSystemSettingsShown: Bool { systemSettingsPopover?.isShown ?? false }
    var debugDisplaySettingsPanel: SettingsPanelViewController? {
        displaySettingsPopover?.contentViewController as? SettingsPanelViewController
    }
    var debugSystemSettingsPanel: SystemSettingsPanelViewController? {
        systemSettingsPopover?.contentViewController as? SystemSettingsPanelViewController
    }
    func debugClosePopovers() {
        displaySettingsPopover?.performClose(nil)
        systemSettingsPopover?.performClose(nil)
    }

    /// 模式切换后的视图显隐与两侧内容（断言"预览跟着换"）
    var debugEditorVisible: Bool { !contentPane.editorViewController.view.isHidden }
    var debugPreviewVisible: Bool { !contentPane.previewViewController.view.isHidden }
    var debugPreviewText: String { contentPane.previewViewController.previewTextView.string }
    var debugEditorText: String { contentPane.editorViewController.text }
    var debugCurrentFileURL: URL? { currentFileURL }

    /// 预览 / 编辑器控制器本体（查找、大纲、编辑器设置读回的断言都挂在它们身上）
    var debugPreview: PreviewViewController { contentPane.previewViewController }
    var debugEditor: EditorViewController { contentPane.editorViewController }

    /// 模式控件三段（write/read/preview）的可用状态——
    /// 非文本文件只留 Read 可点、无文档时三段全灰的断言
    var debugModeControlEnabled: [Bool] { contentPane.debugModeControlEnabled }

    /// 单文件模式（落单文件不开项目、两栏收起）的状态断言
    var debugSingleFileMode: Bool { singleFileMode }

    /// 全局搜索：与 showGlobalSearch 相同的接线，但面板不上屏（见 GlobalSearchPanel.debugPresent）
    func debugShowGlobalSearch(prefill: String) {
        guard let window else { return }
        let workspaces = WorkspaceStore.shared.workspaces
        guard !workspaces.isEmpty else { return }

        let panel = globalSearchPanel ?? GlobalSearchPanel()
        globalSearchPanel = panel
        panel.onOpen = { [weak self] query, hit in
            self?.openSearchHit(hit, query: query)
        }
        panel.debugPresent(over: window, scopes: workspaces.map {
            GlobalSearchEngine.Scope(root: $0.rootURL, name: $0.name)
        }, prefilledQuery: prefill)
    }

    var debugGlobalSearchPanel: GlobalSearchPanel? { globalSearchPanel }

    /// 诊断用：整窗视图树。定位"某个控件没出现 / 尺寸不对"这类问题时，
    /// 直接看 hierarchy 比一层层猜快得多（`MUM_LAYOUT_DEBUG=1` 打开）。
    func dumpViewTree() -> String {
        var lines: [String] = []
        func walk(_ view: NSView, depth: Int) {
            let pad = String(repeating: "  ", count: depth)
            lines.append("\(pad)\(type(of: view))  frame=\(NSStringFromRect(view.frame))")
            for sub in view.subviews { walk(sub, depth: depth + 1) }
        }
        if let content = window?.contentView { walk(content, depth: 0) }
        return lines.joined(separator: "\n")
    }


    /// 诊断用：大纲栏
    var debugTOCVisible: Bool { !contentPane.tocController.view.isHidden }
    var debugTOCState: String { ["open", "rail", "closed"][tocState == .open ? 0 : tocState == .rail ? 1 : 2] }
    var debugTOCRowCount: Int { contentPane.tocController.debugRowCount }
    var debugTOCCurrentTitle: String? { contentPane.tocController.debugCurrentTitle }
    func debugTOCClickRow(_ index: Int) { contentPane.tocController.debugClickRow(index) }
    func debugCloseTOC() { setTOCState(.closed) }

    /// 诊断用：大纲
    var debugOutlineDescription: String { contentPane.previewViewController.debugOutlineSummary }

    /// 诊断用：当前生效的偏好
    var debugSettingsDescription: String {
        "行号=\(settings.showsLineNumbers)  高亮当前行=\(settings.highlightsCurrentLine)  编辑字号=\(settings.editorFontSize)  预览字号=\(settings.previewFontSize)"
    }

    func saveDocument() {
        guard let url = currentFileURL, isDirty else { return }
        // 图片 / PDF / 二进制没有"保存文本"这回事
        guard currentKind?.isTextual ?? false else { return }

        // 文件在别处被改过？先问一句，别静默盖掉。
        // 用 != 不用 >：git checkout / rsync -a 会把 mtime 回写到过去（审计 D-4）。
        // mtime 读不出来也不能放行 —— 静默失效等于没有守卫（审计 D-5）：
        // 文件被删/不可读时保存会重建它，同样要先打招呼。
        if let loaded = loadedModificationDate {
            let onDisk = try? FileManager.default
                .attributesOfItem(atPath: url.path)[.modificationDate] as? Date
            let conflict = onDisk.map { $0 != loaded } ?? true
            if conflict {
                let alert = NSAlert()
                alert.messageText = "「\(url.lastPathComponent)」在磁盘上已被修改"
                alert.informativeText = onDisk == nil
                    ? "磁盘上的版本已被删除或无法读取，保存会用编辑器里的内容重新写入。"
                    : "保存会用编辑器里的内容覆盖磁盘上的版本，那部分改动会丢失。"
                alert.addButton(withTitle: "仍然写入")
                alert.addButton(withTitle: "取消")
                guard alert.runModal() == .alertFirstButtonReturn else { return }
            }
        }

        // 原子写会换 inode，POSIX 权限要先记下来再还回去
        let posix = try? FileManager.default
            .attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber

        do {
            // 用读入时的编码写回，不做静默转码
            try contentPane.editorViewController.text.write(to: url, atomically: true, encoding: loadedEncoding)
            if let posix {
                try? FileManager.default.setAttributes([.posixPermissions: posix], ofItemAtPath: url.path)
            }
            isDirty = false
            loadedModificationDate = try? FileManager.default
                .attributesOfItem(atPath: url.path)[.modificationDate] as? Date
            refreshChrome()
        } catch {
            presentError(message: "保存失败", detail: error.localizedDescription)
        }
    }

    func reloadDocument() {
        guard let url = currentFileURL else { return }
        guard confirmDiscardIfNeeded() else { return }
        // 先彻底关掉再打开：open() 对「同一个文件」会直接返回，
        // 而重新载入恰恰要重走一遍完整流程
        closeCurrentFile()
        open(url: url)
    }

    func closeDocument() {
        guard currentFileURL != nil else { return }
        guard confirmDiscardIfNeeded() else { return }
        closeCurrentFile()
        refreshChrome()
    }

    private func closeCurrentFile() {
        fileWatcher?.stop()
        fileWatcher = nil
        currentFileURL = nil
        currentKind = nil
        loadedModificationDate = nil
        loadedEncoding = .utf8
        isDirty = false
        contentPane.editorViewController.setText("")
    }

    /// 未保存修改的确认。开/关/重载/切模式/关窗/退出六条路都汇到这里；
    /// 返回 true = 可以继续（已保存或用户放弃），false = 用户取消
    func confirmDiscardIfNeeded() -> Bool {
        guard isDirty, let url = currentFileURL else { return true }

        let alert = NSAlert()
        alert.messageText = "「\(url.lastPathComponent)」有未保存的修改"
        alert.informativeText = "离开前要先保存吗？"
        alert.addButton(withTitle: "保存")
        alert.addButton(withTitle: "不保存")
        alert.addButton(withTitle: "取消")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            saveDocument()
            return !isDirty
        case .alertSecondButtonReturn:
            return true
        default:
            return false
        }
    }

    // MARK: - 外部改动

    private func startFileWatcher(for url: URL) {
        fileWatcher?.stop()
        let watcher = FileWatcher(path: url.path, latency: 0.4) { [weak self] in
            self?.handleExternalChange()
        }
        watcher.start()
        fileWatcher = watcher
    }

    private func handleExternalChange() {
        guard let url = currentFileURL else { return }
        // 与打开路径同一个守卫：外部改成二进制就停更，留在当前内容
        // （旧逻辑只认 UTF-8，非 UTF-8 改动会被静默忽略，还会绕过二进制判定）
        guard let decoded = TextDecoding.decode(url: url) else { return }
        guard decoded.text != contentPane.editorViewController.text else { return } // 我们自己的写入

        let kind = FileKind(url: url, isDirectory: false)

        guard !isDirty else {
            let alert = NSAlert()
            alert.messageText = "文件在磁盘上被修改了"
            alert.informativeText = "你本地还有未保存的修改，要放弃它们并载入磁盘版本吗？"
            alert.addButton(withTitle: "载入磁盘版本")
            alert.addButton(withTitle: "保留我的修改")
            if alert.runModal() == .alertFirstButtonReturn {
                loadTextFile(url: url, kind: kind)
                refreshChrome()
            }
            return
        }

        loadTextFile(url: url, kind: kind)
        refreshChrome()
    }

    // MARK: - 视图动作

    func toggleProjects() {
        setPane(0, collapsed: !rootViewController.isPaneCollapsed(0))
    }

    func toggleFileTree() {
        setPane(1, collapsed: !rootViewController.isPaneCollapsed(1))
    }

    private func setPane(_ index: Int, collapsed: Bool) {
        rootViewController.setPaneCollapsed(index, collapsed)
        refreshPaneChrome()
    }

    /// 折叠状态变化后同步布局开关组的高亮，并让内容栏给红绿灯让位
    private func refreshPaneChrome() {
        let projectsVisible = !rootViewController.isPaneCollapsed(0)
        let treeVisible = !rootViewController.isPaneCollapsed(1)

        rootViewController.statusBar.layoutCluster.update(
            projectsVisible: projectsVisible,
            treeVisible: treeVisible
        )

        // 前两栏都收起时内容栏变成最左栏，文件名要让开红绿灯
        contentPane.titleLeadingInset = (projectsVisible || treeVisible)
            ? MuMDesign.contentTitleLeadingInset
            : MuMDesign.trafficLightsReserve
    }

    var isProjectsVisible: Bool { !rootViewController.isPaneCollapsed(0) }
    var isFileTreeVisible: Bool { !rootViewController.isPaneCollapsed(1) }

    func focusFileFilter() {
        setPane(1, collapsed: false)
        fileTreeViewController.focusFilter()
    }

    // MARK: - 快速打开（⌘P）

    /// 按项目缓存的文件索引：换项目重建，面板每次打开时后台刷新
    private var quickOpenIndexes: [String: QuickOpenIndex] = [:]
    private var quickOpenPanel: QuickOpenPanel?

    func showQuickOpen() {
        guard let window, let workspace = WorkspaceStore.shared.active else { return }

        let rootPath = workspace.rootURL.path
        let index = quickOpenIndexes[rootPath] ?? QuickOpenIndex()
        quickOpenIndexes[rootPath] = index

        // 每次打开都后台重扫：1 万文件约百毫秒，面板先用旧缓存，扫完换新
        index.rebuild(root: workspace.rootURL) { [weak self, weak index] _ in
            guard let self, let index, self.quickOpenIndexes[rootPath] === index else { return }
            self.quickOpenPanel?.indexDidUpdate()
        }

        let panel = quickOpenPanel ?? QuickOpenPanel()
        quickOpenPanel = panel
        panel.onOpen = { [weak self] url in
            self?.open(url: url)
        }
        panel.present(over: window, index: index)
    }

    func refreshFileTree() {
        fileTreeViewController.refreshPreservingExpansion()
    }

    // MARK: - 全局搜索（⌘⇧F）

    private var globalSearchPanel: GlobalSearchPanel?
    /// 定位搜索命中时，下一次打开不走渐进渲染 —— 渐进填充是后台分片的，
    /// 命中定位跑在填充完成之前会找不到后半篇的命中
    private var forceFullRenderForNextOpen = false

    func showGlobalSearch(prefill: String? = nil) {
        guard let window else { return }
        let workspaces = WorkspaceStore.shared.workspaces
        guard !workspaces.isEmpty else { return }

        let panel = globalSearchPanel ?? GlobalSearchPanel()
        globalSearchPanel = panel
        panel.onOpen = { [weak self] query, hit in
            self?.openSearchHit(hit, query: query)
        }
        panel.present(over: window, scopes: workspaces.map {
            GlobalSearchEngine.Scope(root: $0.rootURL, name: $0.name)
        }, prefilledQuery: prefill)
    }

    /// 点中一条搜索结果：必要时切到命中所在的项目，打开文件；
    /// 内容命中再定位到那一处 —— 搜索的终点不是文件列表，是"我已经在读那段话了"。
    private func openSearchHit(_ hit: GlobalSearchEngine.Hit, query: String) {
        let store = WorkspaceStore.shared
        guard let index = store.workspaces.firstIndex(where: {
            hit.fileURL.path.hasPrefix($0.rootURL.path + "/")
        }) else { return }

        // 与 openFileFromOutside 同理：切项目不该白付一次旧文件恢复（E-2）
        if index != store.activeIndex {
            suppressNextWorkspaceRestore = true
            store.activate(index: index)
        }

        if hit.kind == .content {
            forceFullRenderForNextOpen = true
        }
        open(url: hit.fileURL)
        forceFullRenderForNextOpen = false

        guard hit.kind == .content else { return }

        // 查找高亮跑在渲染结果上：纯编辑模式下预览里可能还是旧内容，
        // 临时切到阅读模式 —— 不动 preferredMode，看完切回去还是原来的习惯
        if contentPane.mode == .write {
            contentPane.mode = .read
            renderPreview(immediately: true)
            refreshChrome()
        }
        guard canFindInPreview else { return }
        contentPane.previewViewController.reveal(query: query, occurrence: hit.occurrence)
    }

    func revealInFinder() {
        guard let url = currentFileURL else { return }
        ExternalOpener.reveal([url])
    }

    // MARK: - 模式

    var currentMode: ContentViewController.Mode { contentPane.mode }

    func setMode(_ mode: ContentViewController.Mode) {
        guard hasOpenDocument else { return }
        // 非文本文件（PDF / 图片 / 不支持的格式）没有源码可写，
        // 快捷键 ⌥⌘1/3 也一样要拦住 —— 放过去就是一片空白
        guard mode == .read || (currentKind?.isTextual ?? false) else { return }
        contentPane.mode = mode
        applyTOCVisibility()
        if mode != .write {
            renderPreview(immediately: true)
        }
        refreshChrome()
    }

    // MARK: - 大纲栏

    /// 大纲栏三态（用户偏好，跨窗口/跨启动记住）：
    /// open 完整栏 / rail 窄条把手（贴着右缘留把手，不用翻菜单）/ closed 彻底关。
    /// Write 模式没有预览，栏位临时收起，回到 Read/Preview 自动恢复
    private var tocState: ContentViewController.TOCState = {
        switch UserDefaults.standard.string(forKey: "MuM.tocState") {
        case "open": return .open
        case "rail": return .rail
        default: return .closed
        }
    }() {
        didSet { UserDefaults.standard.set(["open", "rail", "closed"][tocState == .open ? 0 : tocState == .rail ? 1 : 2], forKey: "MuM.tocState") }
    }

    /// ⇧⌘O：关 → 开；窄条 → 开；开 → 关
    func toggleTOC() {
        setTOCState(tocState == .open ? .closed : .open)
    }

    /// 菜单勾选状态用：完整栏开着才算「可见」（窄条 = 收起来了）
    var isTOCVisible: Bool { tocState == .open && contentPane.mode != .write }

    func setTOCState(_ state: ContentViewController.TOCState) {
        tocState = state
        applyTOCVisibility()
    }

    private func applyTOCVisibility() {
        contentPane.setTOCState(contentPane.mode == .write ? .closed : tocState)
    }

    // MARK: - 设置

    /// 把偏好同时应用到排版（预览）和编辑器，并落盘。
    private func applySettings(_ newSettings: MuMSettings, persist: Bool = true) {
        let previous = settings
        settings = newSettings
        if persist { SettingsStore.save(newSettings) }

        // nil 就是"跟随系统"
        NSApp.appearance = newSettings.appearance.nsAppearance

        theme.baseSize = newSettings.previewFontSize
        theme.lineSpacing = newSettings.lineSpacing
        theme.blockSpacingScale = newSettings.blockSpacing
        theme.letterSpacing = newSettings.letterSpacing
        theme.previewFont = newSettings.previewFont
        theme.readingTheme = newSettings.readingTheme
        theme.maxContentWidth = CGFloat(newSettings.readingWidth.rawValue)

        FileTreeLoader.showsHiddenFiles = newSettings.showsHiddenFiles
        contentPane.previewViewController.applyReadingTheme(theme)
        contentPane.editorViewController.apply(settings: newSettings)

        // 刚打开"显示行号"、而当前是 Read 模式（看不到编辑区）→ 顺手切到 Write。
        // 否则用户勾了它却什么都没发生，很自然会被当成"设置没生效"。
        // 非文本文件（PDF 等）没有编辑区，别切 —— 切过去就是空白。
        if !previous.showsLineNumbers, newSettings.showsLineNumbers, contentPane.mode == .read,
           currentKind?.isTextual ?? false {
            preferredMode = .write
            contentPane.mode = .write
        }

        renderPreview(immediately: true)
    }

    /// 底栏 **Aa** 弹出的显示设置面板：界面、阅读主题、排版、编辑器显示。
    private func showDisplaySettings(from anchor: NSView) {
        if let existing = displaySettingsPopover, existing.isShown {
            existing.performClose(nil)
            return
        }
        let popover = makePopover()
        popover.contentViewController = makeDisplaySettingsPanel()
        popover.contentSize = popover.contentViewController?.preferredContentSize ?? NSSize(width: 460, height: 470)
        // .maxY 是锚点的上边缘 —— 齿轮在窗口底边，从上方弹出才不会被屏幕下沿压扁
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        displaySettingsPopover = popover
    }

    /// 底栏齿轮弹出的系统设置面板：启动、文件、缩进、系统集成。
    private func showSystemSettings(from anchor: NSView) {
        if let existing = systemSettingsPopover, existing.isShown {
            existing.performClose(nil)
            return
        }
        let popover = makePopover()
        popover.contentViewController = makeSystemSettingsPanel()
        popover.contentSize = popover.contentViewController?.preferredContentSize ?? NSSize(width: 332, height: 420)
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
        systemSettingsPopover = popover
    }

    /// 用 popover 而不是 NSMenu：齿轮在窗口**底边**上，菜单只能往下弹，一到屏幕下沿
    /// 就被压成一条要滚动的东西；而且菜单放不了滑块和开关。
    private func makePopover() -> NSPopover {
        let popover = NSPopover()
        popover.behavior = .transient
        return popover
    }

    private func makeDisplaySettingsPanel() -> SettingsPanelViewController {
        let panel = SettingsPanelViewController(settings: settings)
        panel.onChange = { [weak self] newSettings in
            self?.applySettings(newSettings)
        }
        return panel
    }

    private func makeSystemSettingsPanel() -> SystemSettingsPanelViewController {
        let panel = SystemSettingsPanelViewController(settings: settings)
        panel.onChange = { [weak self] newSettings in
            self?.applySettings(newSettings)
        }
        return panel
    }

    /// 设置面板开着时，用最新值重建它 —— 否则面板上的滑块会和实际值对不上
    private func refreshSettingsPanelIfNeeded() {
        if let popover = displaySettingsPopover, popover.isShown {
            let panel = makeDisplaySettingsPanel()
            popover.contentViewController = panel
            popover.contentSize = panel.preferredContentSize
        }
        if let popover = systemSettingsPopover, popover.isShown {
            let panel = makeSystemSettingsPanel()
            popover.contentViewController = panel
            popover.contentSize = panel.preferredContentSize
        }
    }

    /// 菜单栏的 ⌘+ / ⌘- 也走同一份偏好
    func changePreviewFontSize(by delta: CGFloat) {
        let range = MuMSettings.previewFontSizeRange
        var updated = settings
        updated.previewFontSize = min(max(settings.previewFontSize + delta, range.lowerBound), range.upperBound)
        applySettings(updated)
        refreshSettingsPanelIfNeeded()
    }

    func resetPreviewFontSize() {
        var updated = settings
        updated.previewFontSize = MuMSettings().previewFontSize
        applySettings(updated)
        refreshSettingsPanelIfNeeded()
    }

    // MARK: - 窗口外观

    private func refreshChrome() {
        guard let window else { return }

        let workspace = WorkspaceStore.shared.active
        window.isDocumentEdited = isDirty

        contentPane.update(
            fileURL: currentFileURL,
            isDirty: isDirty,
            hasProject: workspace != nil
        )

        if let url = currentFileURL {
            window.title = url.lastPathComponent
            window.subtitle = workspace?.name ?? url.deletingLastPathComponent().path
        } else {
            window.title = "MuM"
            window.subtitle = workspace?.name ?? "未打开项目"
        }

        updateStatusBar()
    }

    private func updateStatusBar() {
        let workspace = WorkspaceStore.shared.active
        let text = contentPane.editorViewController.text

        var hasher = Hasher()
        hasher.combine(workspace?.rootURL.path)
        hasher.combine(currentFileURL?.path)
        hasher.combine(text)
        hasher.combine(contentPane.mode.title)
        let fingerprint = hasher.finalize()
        guard fingerprint != lastStatusFingerprint else { return }
        lastStatusFingerprint = fingerprint

        LaunchTimer.mark("    updateStatusBar 开始")

        var location: String?
        if let url = currentFileURL, let workspace {
            let root = workspace.rootURL.path
            location = url.path.hasPrefix(root + "/") ? String(url.path.dropFirst(root.count + 1)) : url.path
        }

        rootViewController.statusBar.update(
            project: workspace?.name,
            location: location,
            detail: statusDetail()
        )
        LaunchTimer.mark("    updateStatusBar 完成")
    }

    private func statusDetail() -> String {
        let modeName = contentPane.mode.title
        guard currentFileURL != nil else { return modeName }

        let text = contentPane.editorViewController.text
        guard !text.isEmpty else { return modeName }

        // 单遍扫描，不做任何中间分配 —— 原先 components(separatedBy:) 会给 1MB
        // 文档建一个 6.5 万个字符串的数组（单次 ≈40ms），打开路径上还要被连调三次
        var characters = 0
        var lines = 1
        for scalar in text.unicodeScalars {
            if scalar.value == 0x0A { lines += 1 }
            if !CharacterSet.whitespacesAndNewlines.contains(scalar) { characters += 1 }
        }
        return "\(formatted(characters)) 字 · \(formatted(lines)) 行 · \(modeName)"
    }

    private func formatted(_ value: Int) -> String {
        numberFormatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    private func presentError(message: String, detail: String) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = detail
        alert.addButton(withTitle: "好")
        alert.runModal()
    }
}

// MARK: - NSWindowDelegate

extension MainWindowController: NSWindowDelegate {

    /// 点红灯 / ⌘W 关窗：有未保存修改时先问。⌘Q 不走这里，
    /// 走 AppDelegate 的 applicationShouldTerminate —— 两边同一个确认框。
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        confirmDiscardIfNeeded()
    }
}

// MARK: - ··· 菜单项可用性

extension MainWindowController: NSMenuItemValidation {

    /// ··· 菜单的导出项：无文档 / 非文本（图片、PDF）时置灰
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        switch menuItem.action {
        case #selector(exportAsPNG(_:)), #selector(exportAsPDF(_:)):
            return canExport
        default:
            return true
        }
    }
}
