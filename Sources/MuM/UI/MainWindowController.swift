import AppKit

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
    /// 本次打开要恢复到的阅读位置。渲染是异步的，所以先存着，等 performRender 时用掉
    private var pendingScrollFraction: CGFloat?
    private var workspaceWatcher: FileWatcher?


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

    // MARK: - 初始化

    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1440, height: 900),
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

        LaunchTimer.mark("  开始 applyWorkspace（读文件 + 渲染）")
        applyWorkspace(WorkspaceStore.shared.active)
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
            NSWorkspace.shared.activateFileViewerSelecting([WorkspaceStore.shared.workspaces[index].rootURL])
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
            NSWorkspace.shared.open(url)
        }

        rootViewController.statusBar.onShowDisplaySettings = { [weak self] anchor in
            self?.showDisplaySettings(from: anchor)
        }
        rootViewController.statusBar.onShowSettings = { [weak self] anchor in
            self?.showSystemSettings(from: anchor)
        }

        let editor = contentPane.editorViewController
        editor.onTextChanged = { [weak self] _ in
            self?.markDirty()
        }
        editor.onScroll = { [weak self] fraction in
            guard let self, self.contentPane.isSideBySide else { return }
            self.contentPane.previewViewController.scrollToFractionFromEditor(fraction)
        }

        contentPane.previewViewController.onOpenInternalLink = { [weak self] url in
            guard let self else { return false }
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
                  !isDirectory.boolValue else { return false }
            self.open(url: url)
            return true
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
        if isDirty, !confirmDiscardIfNeeded() { return }
        closeCurrentFile()
        applyWorkspace(WorkspaceStore.shared.active)
        refreshChrome()
    }

    private func applyWorkspace(_ workspace: Workspace?) {
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

        restoreReadingPosition(for: workspace)
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
    /// 它可能不属于任何已打开的项目 —— 那就把它所在的文件夹作为项目打开，
    /// 否则用户双击一个 .md 会什么都没发生。
    func openFileFromOutside(_ url: URL) {
        let file = url.standardizedFileURL
        let store = WorkspaceStore.shared

        if let index = store.workspaces.firstIndex(where: {
            file.path.hasPrefix($0.rootURL.path + "/")
        }) {
            store.activate(index: index)
        } else {
            store.open(url: file.deletingLastPathComponent())
        }

        open(url: file)
    }

    func open(url: URL) {
        let standardized = url.standardizedFileURL
        guard standardized != currentFileURL else { return }
        guard confirmDiscardIfNeeded() else { return }

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

        case .unsupported, .folder:
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

    private func loadTextFile(url: URL, kind: FileKind) {
        guard let text = readText(at: url) else {
            contentPane.previewViewController.showMessage(
                symbol: "exclamationmark.triangle",
                title: "无法读取文件",
                subtitle: url.lastPathComponent
            )
            currentFileURL = url
            contentPane.mode = .read
            return
        }

        currentFileURL = url
        isDirty = false
        loadedModificationDate = try? FileManager.default
            .attributesOfItem(atPath: url.path)[.modificationDate] as? Date
        contentPane.editorViewController.setEditable(true)
        contentPane.editorViewController.setText(text)
        pendingScrollFraction = WorkspaceStore.shared.readingPosition(for: url).map { CGFloat($0) }
        renderPreview(immediately: true)
    }

    /// 优先 UTF-8，失败再让系统探测编码，最后用 Latin-1 兜底
    private func readText(at url: URL) -> String? {
        if let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        var encoding: UInt = 0
        if let text = try? NSString(contentsOf: url, usedEncoding: &encoding) {
            return text as String
        }
        if let data = try? Data(contentsOf: url),
           let fallback = String(data: data, encoding: .isoLatin1) {
            return fallback
        }
        return nil
    }

    // MARK: - 渲染预览

    private func markDirty() {
        if !isDirty {
            isDirty = true
            refreshChrome()
        }
        renderPreview(immediately: false)
    }

    private func renderPreview(immediately: Bool) {
        renderWorkItem?.cancel()

        // 预览重排和状态栏的字数统计都放进同一个去抖窗口：
        // 两者都是 O(文档长度)，没必要每个按键都跑一遍
        let work = DispatchWorkItem { [weak self] in
            self?.performRender()
            self?.updateStatusBar()
        }
        renderWorkItem = work

        if immediately {
            DispatchQueue.main.async(execute: work)
        } else {
            // 打字时每 110ms 才重排一次预览，输入永远优先
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.11, execute: work)
        }
    }

    private func performRender() {
        guard let url = currentFileURL else { return }
        guard contentPane.mode != .write else { return }
        guard FileKind(url: url, isDirectory: false).isTextual else { return }

        contentPane.previewViewController.previewTextView.maxContentWidth = theme.maxContentWidth

        let renderer = MarkdownRenderer(theme: theme, baseURL: url.deletingLastPathComponent())
        let text = contentPane.editorViewController.text
        let kind = FileKind(url: url, isDirectory: false)

        let attributed: NSAttributedString
        switch kind {
        case .markdown:
            attributed = renderer.render(text)
        case .code:
            attributed = renderer.renderCode(text, language: FileKind.language(for: url))
        default:
            attributed = renderer.renderPlainText(text)
        }

        let restore = pendingScrollFraction
        pendingScrollFraction = nil
        contentPane.previewViewController.show(attributed: attributed, restoreFraction: restore)
    }

    // MARK: - 保存

    var hasOpenDocument: Bool { currentFileURL != nil }

    /// 记住当前读到哪。切文件和退出应用时各存一次 ——
    /// 这就够覆盖"关掉再打开落回原位置"，不需要在每次滚动时写 UserDefaults。
    func saveReadingPosition() {
        guard let url = currentFileURL else { return }
        let fraction = contentPane.mode == .write
            ? contentPane.editorViewController.scrollFraction()
            : contentPane.previewViewController.scrollFraction()
        WorkspaceStore.shared.rememberReadingPosition(Double(fraction), for: url)
    }

    /// 诊断用：模拟设置面板在**运行时**改动偏好。
    /// 启动时读设置和运行时改设置是两条路径，前者通不代表后者通。
    func debugApplySettings(_ mutate: (inout MuMSettings) -> Void) {
        var updated = settings
        mutate(&updated)
        applySettings(updated, persist: false)
    }

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


    /// 诊断用：当前生效的偏好
    var debugSettingsDescription: String {
        "行号=\(settings.showsLineNumbers)  高亮当前行=\(settings.highlightsCurrentLine)  编辑字号=\(settings.editorFontSize)  预览字号=\(settings.previewFontSize)"
    }

    func saveDocument() {
        guard let url = currentFileURL, isDirty else { return }
        // 图片 / PDF / 二进制没有"保存文本"这回事
        guard currentKind?.isTextual ?? false else { return }

        // 文件在别处被改过？先问一句，别静默盖掉。
        if let loaded = loadedModificationDate,
           let onDisk = try? FileManager.default.attributesOfItem(atPath: url.path)[.modificationDate] as? Date,
           onDisk > loaded {
            let alert = NSAlert()
            alert.messageText = "「\(url.lastPathComponent)」在磁盘上已被修改"
            alert.informativeText = "保存会用编辑器里的内容覆盖磁盘上的版本，那部分改动会丢失。"
            alert.addButton(withTitle: "仍然覆盖")
            alert.addButton(withTitle: "取消")
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }

        do {
            try contentPane.editorViewController.text.write(to: url, atomically: true, encoding: .utf8)
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
        isDirty = false
        contentPane.editorViewController.setText("")
    }

    private func confirmDiscardIfNeeded() -> Bool {
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
        guard let disk = try? String(contentsOf: url, encoding: .utf8) else { return }
        guard disk != contentPane.editorViewController.text else { return } // 我们自己的写入

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

    func refreshFileTree() {
        fileTreeViewController.refreshPreservingExpansion()
    }

    func revealInFinder() {
        guard let url = currentFileURL else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - 模式

    var currentMode: ContentViewController.Mode { contentPane.mode }

    func setMode(_ mode: ContentViewController.Mode) {
        guard hasOpenDocument else { return }
        contentPane.mode = mode
        if mode != .write {
            renderPreview(immediately: true)
        }
        refreshChrome()
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
        if !previous.showsLineNumbers, newSettings.showsLineNumbers, contentPane.mode == .read {
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
    }

    private func statusDetail() -> String {
        let modeName = contentPane.mode.title
        guard currentFileURL != nil else { return modeName }

        let text = contentPane.editorViewController.text
        guard !text.isEmpty else { return modeName }

        let characters = text.unicodeScalars.lazy
            .filter { !CharacterSet.whitespacesAndNewlines.contains($0) }
            .count
        let lines = text.components(separatedBy: "\n").count
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
