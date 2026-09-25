import AppKit

/// 第 3 栏：文件内容。
///
/// 顶部一条工具栏承载三件事：当前文件是谁、用哪种模式看、以及字号。
/// 模式而不是"分屏开关"—— 用户的心智是"我要读"还是"我要写"，不是"右侧面板开不开"。
///
/// - `write`   只看源码
/// - `read`    只看渲染结果（默认，打开文件先看内容）
/// - `preview` 源码与渲染并排对照
final class ContentViewController: NSViewController {

    enum Mode: Int, CaseIterable {
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

        var symbolName: String {
            switch self {
            case .write: return "square.and.pencil"
            case .read: return "book"
            case .preview: return "rectangle.split.2x1"
            }
        }
    }

    var onModeChanged: ((Mode) -> Void)?

    let editorViewController = EditorViewController()
    let previewViewController = PreviewViewController()
    /// 右侧大纲栏（可折叠，⌥⌘O）。常驻导航：跟随滚动高亮当前节
    let tocController = OutlinePanelController()

    private let fileIcon = NSImageView()
    private let fileNameLabel = NSTextField(labelWithString: "")
    private let dirtyDot = NSView()
    /// 「用默认应用打开」。只对非 Markdown 文件显示 ——
    /// MuM 在这里只给出源码，要看渲染结果（比如 HTML 的页面、SVG 的图形）
    /// 得交给系统。自己写 HTML 渲染器会毁掉"无 Web 引擎"这条护城河。
    private let externalOpenButton = NSButton()
    var onOpenExternally: (() -> Void)?
    private let modeControl = NSSegmentedControl()
    /// 右上角的「导出」按钮（下拉菜单由窗口控制器装配：PNG / PDF）。
    /// 文字按钮而不是 ··· 图标 —— 图标的含义要猜，文字不用（ice 2026-09-25）
    let exportButton = NSButton()
    /// 内容区顶部到 view 顶部的距离，等于标题带的高度（运行期按安全区自适应）
    private var stripHeightConstraint: NSLayoutConstraint!
    /// 标题带内控件的垂直中心
    private var stripCenterConstraint: NSLayoutConstraint!
    /// 标题带内控件的左边界
    private var titleLeadingConstraint: NSLayoutConstraint!

    /// 标题带里控件距离左边缘多少。
    ///
    /// 前两栏都收起时，内容栏会变成窗口的最左栏，它的文件名正好落在红绿灯底下 ——
    /// 所以这种情况下要按红绿灯的宽度让位。由 MainWindowController 按折叠状态设置。
    var titleLeadingInset: CGFloat = MuMDesign.contentTitleLeadingInset {
        didSet { titleLeadingConstraint?.constant = titleLeadingInset }
    }
    private let splitView = NSSplitView()
    // 用带底色的视图而不是裸 NSView —— 它的职责是**盖住**整栏，
    // 包括底下预览区那句「无文件」提示。裸 NSView 是透明的，
    // 两层空状态会叠在一起显示（真实发生过）。
    private let emptyState = PaneBackgroundView(color: MuMDesign.paneBackground)
    private let emptyIcon = NSImageView()
    private let emptyTitle = NSTextField(labelWithString: "")
    private let emptySubtitle = NSTextField(labelWithString: "")

    /// 并排模式下是否已经给过一次初始分割位置
    private var didSetInitialSplit = false

    var mode: Mode = .read {
        didSet { applyMode() }
    }

    // MARK: - 生命周期

    override func loadView() {
        view = NSView()
        buildTitleStrip()
        buildContent()
        buildEmptyState()
        applyMode()
    }

    override func viewDidLayout() {
        super.viewDidLayout()

        // 内容区从标题带下面开始。标题带 = 系统安全区（标准标题栏高度）+
        // 自己的下探空间（titleStripExtra），拿不到安全区时退回常量 ——
        // 不在代码里写死 28，标题栏样式变了也不会错位。
        let inset = view.safeAreaInsets.top
        let strip = (inset > 1 ? inset : MuMDesign.titleStripHeight) + MuMDesign.titleStripExtra
        guard abs(stripHeightConstraint.constant - strip) > 0.5 else { return }

        stripHeightConstraint.constant = strip
        stripCenterConstraint.constant = strip / 2
    }

    // MARK: - 标题带

    /// 内容栏的所有控件都住在窗口顶部那条标题带里，不再单独占一行。
    ///
    /// 这是从 Lineform 学来的：标题带横跨整个窗口，左侧是红绿灯、右侧是布局开关组，
    /// 中间这条带子本来就是空着的 —— 把文件名、模式切换、操作菜单放进来，内容区就
    /// 白赚一整行（40pt）的高度，而且不会有两层横条叠在一起的分裂感。
    ///
    /// 三段式布局：左 = 文档图标 + 文件名（这一栏的主角，16pt semibold）；
    /// 中 = Write/Read/Preview 模式开关（文档的"主视角开关"，水平居中）；
    /// 右 = ··· 操作菜单（导出等）。
    private func buildTitleStrip() {
        fileIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 13, weight: .regular)
        fileIcon.contentTintColor = MuMDesign.secondaryText

        fileNameLabel.font = MuMDesign.contentTitleLarge
        fileNameLabel.textColor = MuMDesign.primaryText
        fileNameLabel.lineBreakMode = .byTruncatingMiddle
        fileNameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        externalOpenButton.image = NSImage(
            systemSymbolName: "arrow.up.forward.app",
            accessibilityDescription: "用默认应用打开"
        )
        externalOpenButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
        externalOpenButton.isBordered = false
        externalOpenButton.bezelStyle = .inline
        externalOpenButton.contentTintColor = MuMDesign.secondaryText
        externalOpenButton.target = self
        externalOpenButton.action = #selector(openExternally)
        externalOpenButton.isHidden = true
        externalOpenButton.translatesAutoresizingMaskIntoConstraints = false
        externalOpenButton.widthAnchor.constraint(equalToConstant: 22).isActive = true

        dirtyDot.wantsLayer = true
        dirtyDot.layer?.cornerRadius = 3
        dirtyDot.layer?.backgroundColor = MuMDesign.accent.cgColor
        dirtyDot.isHidden = true

        // 模式开关居中，控件本身调大一号：大号控件 + 更宽的分段 + 加粗一档的字，
        // 让它读起来是"主开关"而不是工具栏附件。保持原生 NSSegmentedControl，不自绘。
        modeControl.segmentStyle = .rounded
        modeControl.trackingMode = .selectOne
        modeControl.controlSize = .large
        modeControl.font = .systemFont(ofSize: 13, weight: .medium)
        modeControl.segmentCount = Mode.allCases.count
        for (index, mode) in Mode.allCases.enumerated() {
            modeControl.setLabel(mode.title, forSegment: index)
            modeControl.setWidth(78, forSegment: index)
        }
        modeControl.selectedSegment = mode.rawValue
        modeControl.target = self
        modeControl.action = #selector(modeControlChanged)
        modeControl.toolTip = "Write 写源码 · Read 阅读 · Preview 并排对照（⌘⌥1 / ⌘⌥2 / ⌘⌥3）"

        // 右上 ···：操作菜单（导出为 PNG/PDF）。菜单内容由窗口控制器装配 ——
        // 它知道当前文档能不能导出。样式与文件树栏头部的 ··· 一致。
        exportButton.title = "导出"
        exportButton.bezelStyle = .rounded
        exportButton.controlSize = .small
        exportButton.font = NSFont.systemFont(ofSize: 12)
        exportButton.translatesAutoresizingMaskIntoConstraints = false
        // NSButton 挂上 menu 不会在点击时自动弹出（那是 NSPopUpButton 的行为），
        // 得自己接住点击再 popUp —— 实测点击无反应的坑就在这
        exportButton.target = self
        exportButton.action = #selector(showMoreMenu(_:))

        let leftGroup = NSStackView(views: [fileIcon, fileNameLabel, dirtyDot, externalOpenButton])
        leftGroup.orientation = .horizontal
        leftGroup.alignment = .centerY
        leftGroup.spacing = 7
        leftGroup.setHuggingPriority(.defaultLow, for: .horizontal)
        leftGroup.translatesAutoresizingMaskIntoConstraints = false

        modeControl.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(leftGroup)
        view.addSubview(modeControl)
        view.addSubview(exportButton)

        stripCenterConstraint = leftGroup.centerYAnchor.constraint(
            equalTo: view.topAnchor,
            constant: (MuMDesign.titleStripHeight + MuMDesign.titleStripExtra) / 2
        )

        titleLeadingConstraint = leftGroup.leadingAnchor.constraint(
            equalTo: view.leadingAnchor,
            constant: titleLeadingInset
        )

        NSLayoutConstraint.activate([
            stripCenterConstraint,
            titleLeadingConstraint,

            // 左组不能压到居中的模式开关
            leftGroup.trailingAnchor.constraint(lessThanOrEqualTo: modeControl.leadingAnchor, constant: -12),

            // 中：模式开关，钉在标题带的水平中心
            modeControl.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            modeControl.centerYAnchor.constraint(equalTo: leftGroup.centerYAnchor),

            // 右：··· 操作菜单
            exportButton.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14),
            exportButton.centerYAnchor.constraint(equalTo: leftGroup.centerYAnchor),
            exportButton.leadingAnchor.constraint(greaterThanOrEqualTo: modeControl.trailingAnchor, constant: 12),
        ])
    }

    // MARK: - 内容区

    private func buildContent() {
        addChild(editorViewController)
        addChild(previewViewController)
        addChild(tocController)

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.translatesAutoresizingMaskIntoConstraints = false
        splitView.addSubview(editorViewController.view)
        splitView.addSubview(previewViewController.view)

        view.addSubview(splitView)

        // 大纲栏三态：开（220pt）/ 窄条（26pt 把手）/ 关。钉在内容区右缘、工具栏条之下
        let tocView = tocController.view
        tocView.translatesAutoresizingMaskIntoConstraints = false
        tocView.isHidden = true
        view.addSubview(tocView)

        // 窄条：只留两个小手按钮 —— 「‹」拉回完整栏、「×」彻底关掉
        railView.isHidden = true
        railView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(railView)
        setupRail()

        tocOpenConstraints = [
            splitView.trailingAnchor.constraint(equalTo: tocView.leadingAnchor),
            tocView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            tocView.topAnchor.constraint(equalTo: view.topAnchor, constant: MuMDesign.titleStripHeight),
            tocView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            tocView.widthAnchor.constraint(equalToConstant: 220),
        ]
        tocRailConstraints = [
            splitView.trailingAnchor.constraint(equalTo: railView.leadingAnchor),
            railView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            railView.topAnchor.constraint(equalTo: view.topAnchor, constant: MuMDesign.titleStripHeight),
            railView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            railView.widthAnchor.constraint(equalToConstant: 26),
        ]
        splitFullWidthConstraint = splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor)

        stripHeightConstraint = splitView.topAnchor.constraint(
            equalTo: view.topAnchor,
            constant: MuMDesign.titleStripHeight
        )

        NSLayoutConstraint.activate([
            stripHeightConstraint,
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitFullWidthConstraint!,
            splitView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }

    /// 大纲栏三态：open 完整栏 / rail 窄条把手 / closed 彻底关
    enum TOCState { case open, rail, closed }

    /// 窄条把手。两个竖排小按钮：展开回完整栏 / 彻底关闭
    private let railView: NSView = {
        let v = PaneBackgroundView(color: MuMDesign.paneBackground)
        return v
    }()
    private let railExpandButton = NSButton()
    private let railCloseButton = NSButton()
    /// 窄条两个按钮的动作（窗口控制器接）
    var onTOCExpand: (() -> Void)?
    var onTOCClose: (() -> Void)?

    private var tocOpenConstraints: [NSLayoutConstraint] = []
    private var tocRailConstraints: [NSLayoutConstraint] = []
    private var splitFullWidthConstraint: NSLayoutConstraint?
    private var tocState: TOCState = .closed

    @objc private func railExpandTapped() { onTOCExpand?() }
    @objc private func railCloseTapped() { onTOCClose?() }

    private func setupRail() {
        for (button, symbol, tip) in [
            (railExpandButton, "chevron.left", "展开大纲栏"),
            (railCloseButton, "xmark", "关闭大纲栏（⇧⌘O 再开）"),
        ] as [(NSButton, String, String)] {
            button.isBordered = false
            button.title = ""
            button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?
                .withSymbolConfiguration(.init(pointSize: 10, weight: .semibold))
            button.contentTintColor = MuMDesign.tertiaryText
            button.toolTip = tip
            button.translatesAutoresizingMaskIntoConstraints = false
            railView.addSubview(button)
        }
        railExpandButton.target = self
        railExpandButton.action = #selector(railExpandTapped)
        railCloseButton.target = self
        railCloseButton.action = #selector(railCloseTapped)
        NSLayoutConstraint.activate([
            railExpandButton.centerXAnchor.constraint(equalTo: railView.centerXAnchor),
            railExpandButton.topAnchor.constraint(equalTo: railView.topAnchor, constant: 8),
            railExpandButton.widthAnchor.constraint(equalToConstant: 20),
            railExpandButton.heightAnchor.constraint(equalToConstant: 20),
            railCloseButton.centerXAnchor.constraint(equalTo: railView.centerXAnchor),
            railCloseButton.topAnchor.constraint(equalTo: railExpandButton.bottomAnchor, constant: 8),
            railCloseButton.widthAnchor.constraint(equalToConstant: 20),
            railCloseButton.heightAnchor.constraint(equalToConstant: 20),
        ])
    }

    /// 切换大纲栏状态。只是布局开合，不打断正文滚动位置
    func setTOCState(_ state: TOCState) {
        guard state != tocState else { return }
        tocState = state
        tocController.view.isHidden = (state != .open)
        railView.isHidden = (state != .rail)
        NSLayoutConstraint.deactivate(tocOpenConstraints + tocRailConstraints)
        splitFullWidthConstraint?.isActive = false
        switch state {
        case .open: NSLayoutConstraint.activate(tocOpenConstraints)
        case .rail: NSLayoutConstraint.activate(tocRailConstraints)
        case .closed: splitFullWidthConstraint?.isActive = true
        }
    }

    private func buildEmptyState() {
        emptyIcon.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 32, weight: .light)
        emptyIcon.contentTintColor = MuMDesign.tertiaryText
        emptyIcon.translatesAutoresizingMaskIntoConstraints = false

        emptyTitle.font = .systemFont(ofSize: 16, weight: .semibold)
        emptyTitle.textColor = MuMDesign.secondaryText
        emptyTitle.alignment = .center

        emptySubtitle.font = .systemFont(ofSize: 12)
        emptySubtitle.textColor = MuMDesign.tertiaryText
        emptySubtitle.alignment = .center
        emptySubtitle.lineBreakMode = .byWordWrapping
        emptySubtitle.maximumNumberOfLines = 3

        let stack = NSStackView(views: [emptyIcon, emptyTitle, emptySubtitle])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 8
        stack.setCustomSpacing(14, after: emptyIcon)
        stack.translatesAutoresizingMaskIntoConstraints = false

        // ⚠️ 必须关掉 autoresizing 约束。不关的话它会和下面四条约束打架，
        // 视图停在 0×0、原点在左下角，子元素居中于一个空盒子 ——
        // 整块空状态跑到内容区左下角、文字被左边缘切掉（真实发生过）。
        emptyState.translatesAutoresizingMaskIntoConstraints = false
        emptyState.addSubview(stack)
        view.addSubview(emptyState)
        NSLayoutConstraint.activate([
            emptyState.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            emptyState.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // 空状态铺满整栏（连工具栏的位置一起盖住）。如果只从分隔线往下铺，
            // 隐藏的工具栏因为约束还在，会白白占掉 46pt 把空状态挤下去。
            emptyState.topAnchor.constraint(equalTo: view.topAnchor),
            emptyState.bottomAnchor.constraint(equalTo: view.bottomAnchor),

            stack.centerXAnchor.constraint(equalTo: emptyState.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: emptyState.centerYAnchor, constant: -24),
            stack.widthAnchor.constraint(lessThanOrEqualToConstant: 340),
        ])
    }

    // MARK: - 模式

    private func applyMode() {
        modeControl.selectedSegment = mode.rawValue

        let showsEditor = mode == .write || mode == .preview
        let showsPreview = mode == .read || mode == .preview

        // NSSplitView 会尊重子视图的 isHidden，自动把空间让给其余子视图
        editorViewController.view.isHidden = !showsEditor
        previewViewController.view.isHidden = !showsPreview
        splitView.adjustSubviews()

        if mode == .preview, !didSetInitialSplit {
            didSetInitialSplit = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let half = self.splitView.bounds.width / 2
                self.splitView.setPosition(half, ofDividerAt: 0)
            }
        }

        // 从并排切回来时重置，下次进并排重新对半
        if mode != .preview {
            didSetInitialSplit = false
        }
    }

    @objc private func modeControlChanged() {
        guard let next = Mode(rawValue: modeControl.selectedSegment) else { return }
        mode = next
        onModeChanged?(next)
    }

    /// 非文本文件（图片 / PDF / 不支持的格式）没有「写」可言：
    /// Write / Preview 两段置灰，只留 Read；已经在别的模式就拽回 Read。
    /// 否则点一下 Write 就是一片空白（编辑区为空且不可编辑），像坏了。
    func setModeControlTextual(_ textual: Bool) {
        // Read 永远可用（可能被「无文档置灰」关过，这里顺手恢复）
        modeControl.setEnabled(true, forSegment: Mode.read.rawValue)
        modeControl.setEnabled(textual, forSegment: Mode.write.rawValue)
        modeControl.setEnabled(textual, forSegment: Mode.preview.rawValue)
        if !textual, mode != .read {
            mode = .read
        }
    }

    /// ··· 点击弹出操作菜单（菜单项的 target 由窗口控制器装配，这里只管弹）
    @objc private func showMoreMenu(_ sender: NSButton) {
        guard let menu = sender.menu else { return }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: sender.bounds.height + 5), in: sender)
    }

    /// uitest 钩子：模式控件各段（write/read/preview）的 enabled 状态
    var debugModeControlEnabled: [Bool] {
        (0 ..< modeControl.segmentCount).map { modeControl.isEnabled(forSegment: $0) }
    }

    // MARK: - 对外状态

    /// 更新顶部工具栏。`fileURL` 为 nil 时显示空状态
    func update(fileURL: URL?, isDirty: Bool, hasProject: Bool) {
        // 空状态盖住整栏，这里不需要隐藏工具栏 —— 隐藏它反而会留下 46pt 的空洞
        emptyState.isHidden = fileURL != nil

        guard let fileURL else {
            // 没有文档时模式控件整体置灰 —— 切模式没有对象，点了像没反应。
            // 重新打开文件时由 setModeControlTextual 按文件类型恢复。
            for segment in 0 ..< modeControl.segmentCount {
                modeControl.setEnabled(false, forSegment: segment)
            }
            if hasProject {
                showEmptyState(
                    symbol: "doc.text.magnifyingglass",
                    title: "选择一篇文档",
                    subtitle: "在中间的目录树里点击文件即可打开"
                )
            } else {
                showEmptyState(
                    symbol: "rectangle.stack.badge.plus",
                    title: "MuM",
                    subtitle: "按 ⌘O 打开一个文件夹作为项目"
                )
            }
            return
        }

        fileNameLabel.stringValue = fileURL.lastPathComponent
        dirtyDot.isHidden = !isDirty
        fileIcon.image = NSImage(systemSymbolName: symbolName(for: fileURL), accessibilityDescription: nil)
    }

    private func symbolName(for url: URL) -> String {
        switch FileKind(url: url, isDirectory: false) {
        case .markdown: return "text.document"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .plainText: return "doc.plaintext"
        case .richText: return "doc.richtext"
        case .image: return "photo"
        case .pdf: return "doc.richtext"
        default: return "doc"
        }
    }

    @objc private func openExternally() {
        onOpenExternally?()
    }

    /// 非 Markdown 文件才显示"交给系统打开" —— Markdown 是 MuM 的主场，不需要。
    func setExternalOpenAvailable(_ available: Bool, tooltip: String?) {
        externalOpenButton.isHidden = !available
        externalOpenButton.toolTip = tooltip
    }

    private func showEmptyState(symbol: String, title: String, subtitle: String) {
        emptyIcon.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        emptyTitle.stringValue = title
        emptySubtitle.stringValue = subtitle
    }

    /// 只有并排模式才需要把编辑器滚动同步到预览
    var isSideBySide: Bool { mode == .preview }
}

// MARK: - 并排比例

extension ContentViewController: NSSplitViewDelegate {

    /// 并排时两侧平分，且都不许被拖没
    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        max(proposedMinimumPosition, splitView.bounds.width * 0.2)
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        min(proposedMaximumPosition, splitView.bounds.width * 0.8)
    }

    func splitView(_ splitView: NSSplitView, shouldHideDividerAt dividerIndex: Int) -> Bool {
        // 单栏模式下不显示分隔线
        mode != .preview
    }

    func splitView(_ splitView: NSSplitView, holdingPriorityForSubviewAt dividerIndex: Int) -> NSLayoutConstraint.Priority {
        NSLayoutConstraint.Priority(251)
    }
}
