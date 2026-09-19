# 技术选型

> 从 README 拆出（它 595 行太长了）。内容一字未改。


参考 [Ghostty 的架构](https://ghostty.org/docs/about)：它的 macOS 应用是
**Swift + AppKit + SwiftUI**，GUI 用系统原生控件而不是自己画。MuM 直接采用
这个思路的 macOS 那一半 —— 不需要 Ghostty 的 Zig 核心层，因为 Markdown 解析
有现成的 cmark-gfm。

| 层 | 选型 | 理由 |
| :--- | :--- | :--- |
| 应用外壳 | **AppKit**（非 SwiftUI App 协议） | 窗口、菜单、响应链完全可控 |
| 分栏 | **朴素 NSSplitView** | 见下方说明 |
| 文件树 | **NSOutlineView** | 原生披露三角、键盘导航、大目录下比 SwiftUI List 稳 |
| 编辑器 | **NSTextView** | 撤销、查找栏、输入法、辅助功能全部免费 |
| 预览 | **NSTextView + 手工绘制** | 见下方说明 |
| Markdown 解析 | **swift-markdown**（cmark-gfm） | 与 GitHub 同源的解析器，AST 完备 |

### 为什么预览不用 WKWebView

WKWebView + marked.js 的排版能力最强，数学公式和 Mermaid 都是现成的。代价是
每个窗口多一个 Web 内容进程（约 40MB），以及一次「Markdown → HTML → 布局」的往返。

选原生 NSTextView 换来的是：**文本选中、⌘F 查找、三指查词、朗读、系统级字体
缩放全部直接可用** —— 这些在 Web 方案里要一个个手工补，而且很难做对。

需要额外补的排版效果只有三样：引用块竖线、分隔线、标题下划线。它们用
`NSLayoutManager` 拿到段落矩形后手工绘制，总共不到 60 行（见
`PreviewTextView.drawDecorations`）。

### 代码块的底色是自己画的

本可以交给 `NSAttributedString.backgroundColor`，但踩了两次坑：

1. **段落缩进 + `.backgroundColor`** —— TextKit 填首行时从 `firstLineHeadIndent` 起算，
   填续行时却从行片段原点起算（忽略 `headIndent`）。续行底色向左多铺一个缩进量，
   代码块左上角就缺了一角。
2. **换成 `NSTextBlock`** —— 纯 `NSTextBlock`（不像 `NSTextTable`）不会自己绘制底色，
   结果是整块底色都没了。

最后用自定义的 `PreviewLayoutManager`，在 `drawBackground(forGlyphRange:at:)` 里
从容器左缘铺到右缘、上下各留 6pt 内边距。这个钩子在 TextKit 绘制文字**之前**，
所以底色天然位于文字下方，位置也完全可控。

顺带一提：底色这种"极浅的灰"（#F4F5F7）在离屏快照里肉眼分辨不出，也验不了 ——
但**几何**能验。用像素探针逐点读色值，比目视可靠得多。

### 为什么分栏用朴素 NSSplitView

最初用了 `NSSplitViewController`（它自带折叠动画、holding priority 这些便利）。
但把它作为子控制器嵌进一层根容器时踩了两个坑，最终换成朴素 `NSSplitView`：

1. `NSSplitViewController` 的 `splitViewItems` 不会被布局 —— 三个子视图停在
   `(0,0)` 且只有拟合尺寸（196×76 之类）。
2. 它还会把这个退化尺寸写进自己的 autosave，之后**每次启动都恢复这个坏值**，
   表现为窗口明明 1440×932，三栏却全挤在底部。

朴素 `NSSplitView` 用 frame 管理子视图，行为完全确定。折叠上又踩了两个坑：

1. **折叠不能靠 `subview.isHidden = true` 加 `adjustSubviews()`** ——
   `adjustSubviews()` 会把刚设好的 `isHidden` 撤销掉，那一栏立刻就回来了，
   表现为折叠按钮点了没反应。只设 `isHidden`、让 NSSplitView 在自己的布局过程里
   处理它，才是对的。
2. **`constrainMinCoordinate` 要把已折叠的栏排除掉** —— 否则折叠第 1 栏之后，
   分隔线仍被推到 `196+214` 的位置，目录树白白宽出一截。
3. 折叠第 1 栏后要主动把分隔线摆回设计位置，否则 NSSplitView 会把让出的空间
   给**紧邻**的目录树；而折叠第 2 栏时反而不能碰分隔线（会把它推回来），
   NSSplitView 本来就会把空间给右侧的内容栏。

### 窗口尺寸的一个陷阱

AppKit 在**每个显示周期**都会走
`__NSWindowGetDisplayCycleObserverForLayout` → `NSWindow.layoutIfNeeded` →
`_changeWindowFrameFromConstraintsIfNecessary` 重算窗口尺寸。这意味着：

- 任何事后的 `setContentSize` / `setFrame` 都会在下一帧被覆盖；
- 它只取「刚好满足」的**最小**尺寸，低优先级（`.defaultLow`）的偏好会被直接忽略。

所以「窗口该多大」必须表达成约束。`RootViewController` 里用 `.defaultHigh`
的等值约束给出理想尺寸 —— 没有别的约束竞争时它就是最终尺寸，用户拖动时它让位。

顺带一提，`NSWindow.setFrameUsingName` 在**没有**保存记录时同样返回 `true`，
不能拿它的返回值判断「有没有历史记录」。

---
