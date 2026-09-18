import AppKit

/// 窗口根视图。自定义子类只为了接住「拖文件/文件夹进窗口」：
/// 拖拽落点得落在 NSView 上 —— NSWindow 的拖拽方法是协议扩展实现，子类重写不到。
final class RootView: NSView {

    /// 拖放落点回调：文件或文件夹的 URL 数组
    var onDropURLs: (([URL]) -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) {
        fatalError("RootView 不走 nib")
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let canRead = sender.draggingPasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
        return canRead ? .copy : []
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else { return false }
        onDropURLs?(urls)
        return true
    }
}

/// 窗口根视图控制器：三栏分栏 + 底部状态栏。
///
/// 状态栏横跨整个窗口宽度，所以它必须在分栏容器**外面** —— 这也是为什么需要这一层。
///
/// 这里刻意用朴素的 `NSSplitView` 而不是 `NSSplitViewController`。
/// 实测把 `NSSplitViewController` 作为子控制器嵌套进来时，它的 `splitViewItems`
/// 不会被布局：三个子视图会停在 `(0,0)` 且只有拟合尺寸（196×76 之类），
/// 并且会把这个退化尺寸写进自己的 autosave，之后每次启动都恢复这个坏值。
final class RootViewController: NSViewController {

    let splitView = NSSplitView()
    let statusBar = StatusBarView()

    /// 拖文件/文件夹进窗口的回调，由窗口控制器接上 `openDropped`。
    /// 根视图在 loadView 时才创建，所以回调存在控制器上，loadView 时桥接过去。
    var onDropURLs: (([URL]) -> Void)?

    private var panes: [NSView] = []
    private var minimumWidths: [CGFloat] = []
    /// 每栏期望的折叠状态。作为唯一事实来源 —— 不去读 NSSplitView 的当前帧，
    /// 因为帧在布局过程中会短暂处于中间态。
    private var desiredCollapsed: [Bool] = []
    private var didApplyInitialPositions = false

    // MARK: - 生命周期

    override func loadView() {
        let root = RootView()
        root.onDropURLs = { [weak self] urls in self?.onDropURLs?(urls) }
        view = root
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        splitView.isVertical = true
        splitView.dividerStyle = .thin
        splitView.delegate = self
        splitView.autosaveName = "MuM.MainSplit"
        splitView.translatesAutoresizingMaskIntoConstraints = false

        statusBar.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(splitView)
        view.addSubview(statusBar)

        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: view.topAnchor),

            statusBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            statusBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            statusBar.topAnchor.constraint(equalTo: splitView.bottomAnchor),
            statusBar.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            statusBar.heightAnchor.constraint(equalToConstant: MuMDesign.statusBarHeight),
        ])

        // 窗口尺寸由约束系统决定，而不是由 setFrame 决定。
        //
        // 实测：AppKit 在每个显示周期都会从
        // __NSWindowGetDisplayCycleObserverForLayout → NSWindow.layoutIfNeeded →
        // _changeWindowFrameFromConstraintsIfNecessary 重算窗口尺寸。任何事后的
        // setContentSize / setFrame 都会在下一帧被覆盖，而且它只取「刚好满足」的最小
        // 尺寸 —— 低优先级（.defaultLow）的偏好会被直接忽略。
        //
        // 所以用 .defaultHigh：没有别的约束竞争时它就是最终尺寸；
        // 用户拖动窗口时，窗口自身的约束优先级更高，这条会让位。
        let preferredWidth = view.widthAnchor.constraint(
            equalToConstant: MuMDesign.defaultWindowContentSize.width
        )
        preferredWidth.priority = .defaultHigh

        let preferredHeight = view.heightAnchor.constraint(
            equalToConstant: MuMDesign.defaultWindowContentSize.height
        )
        preferredHeight.priority = .defaultHigh

        NSLayoutConstraint.activate([preferredWidth, preferredHeight])
    }

    // MARK: - 装配面板

    func install(panes: [NSView], minimumWidths: [CGFloat], maximumWidths: [CGFloat]) {
        precondition(panes.count == minimumWidths.count && panes.count == maximumWidths.count)

        loadViewIfNeeded()

        self.panes = panes
        self.minimumWidths = minimumWidths
        self.desiredCollapsed = Array(repeating: false, count: panes.count)

        for pane in panes {
            // 交给 NSSplitView 用 frame 摆放；面板内部的自动布局不受影响
            pane.translatesAutoresizingMaskIntoConstraints = true
            splitView.addSubview(pane)
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        applyInitialPositionsIfNeeded()
    }

    // MARK: - 折叠
    //
    // 折叠的正确做法是**把分隔线推到让那一栏宽度归零**，而不是设 `subview.isHidden`。
    // 试过的两条错路：
    //   · `isHidden = true` + `adjustSubviews()` —— adjustSubviews 会把 isHidden 撤销掉，
    //     那一栏立刻就回来了，表现为按钮点了没反应。
    //   · 只设 `isHidden = true` —— 视图确实藏了，但 NSSplitView 不会把它占的横向空间
    //     让给别的栏，于是留下一条空白；而一旦再调 `setPosition` 又会把它顶回来。
    // 宽度归零之后 NSSplitView 自己就知道那一栏折叠了，空间也会正确让给相邻栏。

    func setPaneCollapsed(_ index: Int, _ collapsed: Bool) {
        guard panes.indices.contains(index), index < panes.count - 1 else { return }
        guard desiredCollapsed[index] != collapsed else { return }

        desiredCollapsed[index] = collapsed
        applyDesignPositions()
    }

    func isPaneCollapsed(_ index: Int) -> Bool {
        desiredCollapsed.indices.contains(index) ? desiredCollapsed[index] : false
    }

    // MARK: - 分隔线位置

    private func applyInitialPositionsIfNeeded() {
        guard !didApplyInitialPositions, splitView.bounds.width > 200 else { return }
        didApplyInitialPositions = true

        // 有历史记录时 NSSplitView 会自己恢复用户调过的比例，不要覆盖
        guard !splitView.hasStoredPositions else { return }
        applyDesignPositions()
    }

    /// 一次性把所有分隔线摆到位：可见的给设计宽度，收起的压到 0。
    ///
    /// 一次算完而不是逐条改。中途任何"先摆一部分"的状态都可能让 NSSplitView
    /// 把刚折叠好的栏重新撑开。
    private func applyDesignPositions() {
        guard splitView.bounds.width > 200, panes.count > 1 else { return }

        let thickness = splitView.dividerThickness
        let projectsVisible = !desiredCollapsed[0]
        let treeVisible = !desiredCollapsed[1]

        // 项目列表：可见时给设计宽度，收起时归零（分隔线 0 推到最左）
        let projectsWidth = projectsVisible ? MuMDesign.projectsPaneWidth : 0
        splitView.setPosition(projectsWidth, ofDividerAt: 0)

        // 目录树：左边界紧跟在分隔线 0 之后；收起时把右边界也压到同一点
        let treeStart = projectsVisible ? projectsWidth + thickness : 0
        let treeEnd = treeVisible ? treeStart + MuMDesign.treePaneWidth : treeStart
        splitView.setPosition(treeEnd, ofDividerAt: 1)
    }
}

// MARK: - 分栏约束

extension RootViewController: NSSplitViewDelegate {

    func splitView(_ splitView: NSSplitView, constrainMinCoordinate proposedMinimumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        guard dividerIndex < minimumWidths.count else { return proposedMinimumPosition }
        // 分隔线左侧所有**未折叠**面板的最小宽度之和。
        // 必须排除已折叠的栏：否则折叠第 1 栏之后，这条约束仍会把分隔线 1
        // 推到 196+214 的位置，目录树白白宽出一截。
        var required: CGFloat = 0
        for index in 0...dividerIndex where !isPaneCollapsed(index) {
            required += minimumWidths[index]
        }
        required += CGFloat(dividerIndex) * splitView.dividerThickness
        return max(proposedMinimumPosition, required)
    }

    func splitView(_ splitView: NSSplitView, constrainMaxCoordinate proposedMaximumPosition: CGFloat, ofSubviewAt dividerIndex: Int) -> CGFloat {
        let rightStart = dividerIndex + 1
        guard rightStart < minimumWidths.count else { return proposedMaximumPosition }
        // 右侧剩余**未折叠**面板的最小宽度之和
        var required: CGFloat = 0
        for index in rightStart..<minimumWidths.count where !isPaneCollapsed(index) {
            required += minimumWidths[index]
        }
        required += CGFloat(minimumWidths.count - rightStart - 1) * splitView.dividerThickness
        return min(proposedMaximumPosition, splitView.bounds.width - required)
    }

    func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        guard let index = panes.firstIndex(of: subview) else { return false }
        return index < panes.count - 1 // 内容栏不允许折叠
    }

    /// 双击分隔线不做折叠。折叠状态以 `desiredCollapsed` 为准，
    /// 放 NSSplitView 自己折叠会让两者失步，之后就再也对不上了。
    func splitView(_ splitView: NSSplitView, shouldCollapseSubview subview: NSView, forDoubleClickOnDividerAt dividerIndex: Int) -> Bool {
        false
    }

    func splitView(_ splitView: NSSplitView, shouldHideDividerAt dividerIndex: Int) -> Bool {
        // 任一侧面板被折叠时隐藏这条分隔线
        for index in [dividerIndex, dividerIndex + 1] where panes.indices.contains(index) {
            if isPaneCollapsed(index) { return true }
        }
        return false
    }
}

private extension NSSplitView {
    /// 是否已经有用户调整过的分隔线位置记录
    var hasStoredPositions: Bool {
        guard let name = autosaveName, !name.isEmpty else { return false }
        return UserDefaults.standard.string(forKey: "NSSplitView Subview Frames \(name)") != nil
    }
}
