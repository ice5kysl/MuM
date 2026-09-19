# MuM

**A fast, native Markdown engine — for humans and agents.**
**Reading is the point, not a preview.**

> 快、原生、多项目的 Markdown 阅读器 —— **阅读是目的，不是编辑的副产品。**

## 为什么是这三句话

**Fast.** 从进程启动到窗口上屏 **280 毫秒**，渲染本身只占 **0.03 秒**：

```
   0.1 ms  进程启动
  79.2 ms  NSApplication 就绪              dyld + AppKit 初始化
 152.8 ms  控制器对象图构建完成
 171.6 ms  首次布局完成
 204.8 ms  项目恢复 + 读文件 + 全量渲染完成   其中渲染只占 0.03s
 294.1 ms  窗口上屏
```

短到没有启动画面这回事。`MUM_LAUNCH_TIMING=1` 可以自己打一遍。

**Native.** 2.8 MB，全程没有 Web 引擎 —— Markdown 走 cmark-gfm 解析成 `NSAttributedString`，
排版和绘制都在 AppKit 里自己写。这不是性能优化，是**架构选择**：没有 Web 进程，就没有
白屏、没有字体回退、没有滚动不同步。代价是每个排版效果都得自己实现（引用块竖线、
分隔线、代码块底色、GFM 表格都是手绘的）。

**Multi-project.** 项目是主语。大多数 Markdown 应用一次只装一个文件夹，MuM 同时开着多个，
`⌘1`…`⌘9` 秒切 —— 因为项目回答的是"**我在哪**"，而大多数编辑器只回答"这是什么"。

**Reading is the point.** 这一句是界限。在别处，阅读是编辑的副产品 —— `preview` 这个词本身
就是证据，它暗示"真正的工作是写，看只是顺便"。MuM 反过来：阅读是目的，编辑只是偶尔需要。
上面三句都是为它服务的 —— 快是为了读的时候不被打断，原生渲染是为了读得舒服，
多项目是为了知道自己在哪读。

## 和同类的关系

|  | 品类 | 记忆点 | MuM 的位置 |
| :--- | :--- | :--- | :--- |
| Clearly | Mac / iOS / iPadOS 的 Markdown 编辑器 | 多端同步 | 不做移动端，不在这条线上 |
| Lineform | 阅读优化的 Markdown 应用 | 「纸」/ 排版 | 同样认真做排版，但 MuM 是**快 + 原生**打头 |
| Obsidian | 知识库 | 双链 | 不做知识管理 |
| VS Code / Sublime | 代码编辑器 | 可扩展 | 不做插件生态 |
| **MuM** | **多项目 Markdown 阅读器** | **快 + 原生** | 这条线目前是空的 |

"功能多"是能追的，**"架构上不一样"追不了** —— 这是这个定位唯一的、也是足够的理由。

代价也说清楚：**「快」必须一直是真的。** 一旦某次启动变慢、某个操作卡顿，定位就崩，
它比"功能多"难维持得多。

---

---

## 先读这两份

- **[VISION.md](docs/vision.md)** —— 为什么是这个定位，判断标准，明确不做的事
- **[ROADMAP.md](docs/roadmap.md)** —— 0.2 到 1.0 的版本计划与验收标准

下面这份 README 讲的是**怎么用、怎么构建**。

---

## 快速上手

```bash
./scripts/run.sh
```

窗口打开后：

1. **`⌘O` 打开一个项目文件夹** —— 可以开多个，它们并排在第 1 栏，`⌘1`…`⌘9` 切换
2. **在第 2 栏点文件** —— 默认以 **Read**（渲染阅读）打开；顶部 `Write / Read / Preview`
   切换呈现方式，`⌥⌘1/2/3` 也行
3. **想改内容就切到 Write** —— `⌘S` 保存，改动过的文件标题旁有个小圆点
4. **底栏齿轮** 调字号、行距、阅读主题这些偏好（全部立即生效并记住）

三个栏位都能收起，靠**底栏中间那两个小图标**（`⌘0` 收项目列表、`⌥⌘0` 收目录树）——
收起之后内容区会占满窗口，此时文件名会自己给红绿灯让位。

想让 MuM 接管双击 `.md`，见「装到「应用程序」并设为默认编辑器」。

---

## 界面

三栏，各管一件事，互不重叠：

```
┌──────────────────────────────────────────────────────────────┐
│ ●●●                              📄 README.md [Write│Read│Preview] │ ← 顶栏：我在看什么
├──────────┬─────────────┬─────────────────────────────────────┤
│ 项目 2  +│ 📁 demo ⌄ ⋯ │                                     │
├──────────┼─────────────┤                                     │
│ ▸ demo   │ ▾ docs      │            文件内容                 │
│   ~/Code │   a.md      │      （比原来多赚 40pt 高度）        │
│ ▸ blog   │ README.md   │                                     │
├──────────┴─────────────┴─────────────────────────────────────┤
│ demo › README.md   1,243 字 · 80 行 · Read    ▤ ▥ │ ⚙︎        │ ← 底栏：全局状态
└──────────────────────────────────────────────────────────────┘
```

- **第 1 栏 项目列表** —— 两行卡片（名称 + 完整路径），`⌘1`…`⌘9` 切换
- **第 2 栏 目录树** —— 顶部是**项目切换器**（`📁 demo ⌄`），点开就能换项目
- **第 3 栏 文件内容** —— 从顶栏下方一路铺到状态栏，中间没有第二条横条

### 顶栏只有一条，只放"我在看什么"

窗口用 `.fullSizeContentView` + 透明标题栏 + 隐藏标题。标题带横跨整个窗口：左边是
红绿灯，中间这条带子本来是空着的 —— 于是内容栏的文件名和模式切换住进来，不再单独
占一行。内容区因此白赚一整行（40pt），而且顶栏之下直接就是正文，没有"两层栏叠在
一起"的分裂感。字号、阅读宽度这类设置挪去了底栏的齿轮。

各栏自己的顶栏靠在 `safeAreaLayoutGuide` 上，标题带高度由系统给出，代码里不写死 28。
两栏都收起时内容栏变成最左栏，它的文件名按 `trafficLightsReserve` 给红绿灯让位。

### 底栏分三区

| 区 | 内容 | 回答的问题 |
| :--- | :--- | :--- |
| 左 | 项目 › 文件相对路径 | 我在哪 |
| 中 | 字数 / 行数 / 模式 | 这篇有多长、在看哪种呈现 |
| 右 | 布局开关组 ｜ ⚙︎ | 我开着哪些模块 / 我要调什么 |

字数那组放视觉中轴，是因为它随文档变化、最常被瞟一眼；左右两侧分别是"位置"和"控件"，
都是相对静止的。布局开关和设置之间加一条竖线：前者是状态切换（随时点），后者是入口
（偶尔点），性质不同。

布局开关放在底栏而不是顶栏：顶栏要留给文件名和呈现模式，两块控件挤一起会争夺注意力；
底栏本来就是"全局状态"的位置。

### 行号

只在**源码编辑区**（Write 模式）显示，只给段落首行编号 —— 软换行产生的续行不编号，
这和所有编辑器的行为一致。

渲染预览里**没有**行号：Markdown 渲染后的行和源码不是一一对应的，硬编号是假的；
代码文件的预览虽然能逐行对上，但那个视图是用来"读"的，行号只会增加干扰。
需要行号就切到 Write。

行号栏是自定义的 `NSRulerView`（`LineNumberRulerView`）。它贴在滚动视图左侧固定不动，
所以滚动时要手动重画 —— 它不像文档视图那样跟着滚。

### 语法高亮跟阅读主题走，不跟应用外观走

一开始语法配色用的是 `.secondaryLabelColor` 这类语义色，而语义色跟着**应用外观**解析。
于是暗色应用 + "纸"（米白）主题时，注释色解析成浅灰，压在纸上看不清 —— 用户截图报过。
现在四个阅读主题各自带一套语法配色：浅底用 One Light 系，暗底用 One Dark 系，
高对比用加浓版。

### 设置：两个入口

底栏右侧是 `Aa` 和 `⚙` 两个图标，按**改动的对象**分开：

**Aa —— 显示设置**（"内容长什么样"）

| 分组 | 项 |
| :--- | :--- |
| 外观 | 界面（跟随系统 / 亮色 / 暗色）、阅读主题（跟随外观 / 纸 / 静 / 高对比） |
| 排版 | 字号、字体、行距、段间距、字间距、阅读宽度 |
| 编辑器 | 字号、显示行号、高亮当前行、打字机模式 |

**⚙ —— 系统设置**（"应用怎么运转"）

| 分组 | 项 |
| :--- | :--- |
| 启动 | 恢复上次打开的文件、启动时的呈现方式（Write / Read / Preview） |
| 文件 | 显示隐藏文件 |
| 编辑器 | Tab 缩进（2 / 4 空格） |
| 系统集成 | 默认 Markdown 编辑器（设为默认） |

**为什么分两个**：这两类改动的频率完全不同。排版是你调一次就基本不动的、
但会反复回去微调的；启动行为、缩进宽度这种是"设完就忘"的。混在一个面板里，
后者会把前者挤到看不见 —— 而"看不见"正是上一轮真出过的事故。

`Aa` 用文字而不是 SF Symbol：`textformat` 这个符号在中文本地化下会渲染成「格式」，
和"显示设置"对不上。

**面板是两栏的。** 13 项设置排成一列有 866pt 高 —— 齿轮在窗口底边，popover 最多往上
展开 870pt，等于顶到屏幕最上沿；一旦封顶就得滚动，于是设置项被折到可视区之外。
分两栏后总高降到 500pt 左右。系统设置面板只有 6 项，单栏 332pt 就够。

**为什么是 popover 而不是菜单**：齿轮在窗口底边，菜单只能往下弹，一到屏幕下沿就被
压成一条要滚动的东西。popover 由 AppKit 自动选边，而且能放滑块和开关。

设置整体存成 `MuM.settings` 一个字典，读取时不假设类型：值可能是 `Bool`、`NSNumber`，
也可能是手写 plist 留下的字符串（`defaults write` 会把裸写的 `1` 存成 `"1"`）。
类型对不上会**静默读不到**，表现为"设置改了没反应"，很难查。

### 折叠只有一处入口

**底栏中央的布局开关组**是折叠 / 展开的唯一入口。面板头里不放就地折叠按钮 ——
同一件事留两个入口，只会把"我该点哪个"变成新问题。

两个图标本身就在描述三栏布局 —— `leadingthird` 是左边第一栏（项目列表），
`leadinghalf` 是左边前两栏（含目录树），两者在视觉上是嵌套关系，和它们控制的区域
一一对应。当前可见的图标用染色圆角底 + 强调色高亮，收起后变灰无底。

第 2 栏顶部的项目名同时是**项目切换入口**（`📁 demo ⌄`）。第 1 栏收起之后，
这个位置就是唯一的项目切换入口，所以它不是只读标签。

| 动作 | 快捷键 |
| :--- | :--- |
| 显示 / 隐藏项目列表 | `⌘0` |
| 显示 / 隐藏目录树 | `⌥⌘0` |

### 三种呈现方式

| 模式 | 快捷键 | 内容 |
| :--- | :--- | :--- |
| **Write** | `⌥⌘1` | 只看 Markdown 源码 |
| **Read** | `⌥⌘2` | 只看渲染结果（默认） |
| **Preview** | `⌥⌘3` | 源码与渲染并排对照 |

打开文件默认进 Read —— 先看内容，想改再切到 Write。

**模式会被记住**：切到 Write 之后，再点开别的文件仍然是 Write，不会每次都被拽回 Read。
它是一份"偏好"而不是"当前文件的状态"，会持久化到下次启动。只有图片 / PDF 这类
没法编辑的文件才临时用 Read 呈现，且不会覆盖这份偏好。

---

## 功能

- **切换即恢复现场** —— 切回某个项目时自动回到上次在读的那一篇，没有记录则打开 README
- **文件过滤** —— 按文件名递归搜索，带目录预算，超大仓库里也不会卡住界面
- **实时预览** —— 编辑区改动 110ms 后重排预览；并排模式下按比例联动滚动
- **渲染支持** —— 标题、行内样式、嵌套列表、任务列表、引用（含嵌套）、
  代码块语法高亮、GFM 表格、分隔线、本地图片
- **非文本预览** —— 图片、PDF 走原生查看器；代码文件整篇语法高亮
- **磁盘变更跟随** —— FSEvents 监听，外部改动自动刷新；本地有未保存修改时会询问
- **外部链接** —— 相对路径的 Markdown 链接在 MuM 内部打开，读文档不用离开应用

### 全部快捷键

| 动作 | 快捷键 |
| :--- | :--- |
| 打开项目 | `⌘O` |
| 切换到第 N 个项目 | `⌘1` … `⌘9` |
| 上一个 / 下一个项目 | `⇧⌘[` / `⇧⌘]` |
| 移动当前项目的位置 | `⌥⌘[` / `⌥⌘]` |
| 关闭当前项目 | `⇧⌘W` |
| 快速打开（按名字模糊搜索项目内文件） | `⌘P` |
| 全局搜索（跨所有项目搜文件名和内容） | `⇧⌘F` |
| 上一篇 / 下一篇（阅读历史） | `⌘[` / `⌘]` |
| 保存 | `⌘S` |
| 从磁盘重新载入 | `⌘R` |
| 关闭当前文件 | `⌘W` |
| 刷新文件树 | `⇧⌘R` |
| 在访达中显示 | `⇧⌘J` |
| 显示 / 隐藏项目列表 | `⌘0` |
| 显示 / 隐藏目录树 | `⌥⌘0` |
| Write / Read / Preview | `⌥⌘1` / `⌥⌘2` / `⌥⌘3` |
| 预览字号 | `⌘+` / `⌘-` |
| 全屏幕 | `⌃⌘F` |

编辑器行为：`Tab` 插入两个空格（不跳焦点）；在列表项里回车自动延续标记，
有序列表序号递增；在空列表项上回车退出列表。

---

## 技术选型

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

## 构建与运行

```bash
./scripts/run.sh              # 构建 release 并启动
./scripts/build-app.sh debug  # 只构建，产出 dist/MuM.app
```

只需要 Xcode 命令行工具（Swift 6.0+），不需要打开 Xcode，也没有 `.xcodeproj`
需要维护 —— 整个应用就是 `swift build` 加一个 Info.plist。

### 装到「应用程序」并设为默认编辑器

```bash
./scripts/build-app.sh release
cp -R dist/MuM.app /Applications/        # 建议放这里，见下
```

**为什么要移进 `/Applications`**：macOS 按**路径**记住"这类文件用哪个应用打开"。
留在 `dist/` 里也能设为默认，但仓库一旦被移动或清理，绑定就指向一个不存在的路径了。

`Info.plist` 里声明了三组文档类型，全部用 `LSHandlerRank = Alternate`：

| 类型 | UTI | 角色 |
| :--- | :--- | :--- |
| Markdown / 纯文本 | `net.daringfireball.markdown`、`public.plain-text`、`public.text` | Editor |
| 源代码 | `public.source-code`、`public.json`、`public.yaml` … | Editor |
| 文件夹 | `public.folder` | Viewer |

**为什么不用 `Owner`**：`Owner` 的意思是"这类文件归我"，会去抢系统默认；`Alternate`
只表示"我能打开"。于是 MuM 出现在「打开方式」里，但不主动劫持你已有的选择 ——
这类声明应该是"可选"，不是"夺权"。

同时写了 `LSItemContentTypes`（现代 UTI）和 `CFBundleTypeExtensions`（旧式扩展名）：
只写 UTI 时，某些动态生成的 UTI 不会出现在「打开方式」里，扩展名是兜底。

**设成默认有两种方式**：

1. **MuM 菜单：文件 → 设为默认 Markdown 编辑器**。走
   `NSWorkspace.setDefaultApplication(at:toOpen:)`（macOS 12+）——
   这是唯一公开的、应用能自己调用的方式。已经是默认时该项会打勾并置灰。
2. **访达手动指定**：选中任意 `.md` → 显示简介 → 「打开方式」选 MuM → 点「全部更改」。

只在第 1 种里设了 Markdown 一种。把 `.txt` 和源代码也一并抢过来是越界的 ——
那些类型用户多半已经有别的主力工具，而声明（出现在「打开方式」里）已经够用了。

### 命令行入口：`mum`

```bash
ln -sf /Applications/MuM.app/Contents/Resources/mum /usr/local/bin/mum

mum .            # 把当前目录作为项目打开
mum README.md    # 打开单个文件
```

脚本本体住在 bundle 里（`Contents/Resources/mum`），跟应用同版本发布。
它走 LaunchServices（`open -a`）：应用没在跑就拉起，在跑就把打开事件递给
现有实例 —— 不会出现第二个进程、第二个 Dock 图标。

**为什么在 `Resources` 而不是 `MacOS`**：macOS 默认文件系统大小写不敏感，
`Contents/MacOS/mum` 和主二进制 `Contents/MacOS/MuM` 是同一个文件 ——
放进去会直接覆盖掉应用本体（踩过，勿试）。

验证当前绑定：

```bash
# 系统认为 .md 现在由谁打开
mdls -name kMDItemContentType README.md          # → net.daringfireball.markdown
```

```swift
// 或者用 Swift 查
import AppKit, UniformTypeIdentifiers
let md = UTType("net.daringfireball.markdown")!
NSWorkspace.shared.urlForApplication(toOpen: md)        // 当前的默认应用
NSWorkspace.shared.urlsForApplications(toOpen: md)      // 全部候选，MuM 应在其列
```

### 自检与离屏快照

预览区的正确性体现在 `NSAttributedString` 的属性上，肉眼看截图只能看个大概。
`--selftest` 不启动窗口，直接对渲染结果做 24 项断言：

```bash
.build/release/MuM --selftest                              # 跑断言
.build/release/MuM --selftest Examples/demo/README.md      # 打印结构报告
```

`--snapshot` 把整个窗口离屏渲染成 PNG，不需要屏幕点亮，也不弹窗 ——
锁屏、SSH、CI 里都能检查界面：

```bash
dist/MuM.app/Contents/MacOS/MuM --snapshot /tmp/mum.png
```

注意要用 app bundle 里的二进制：直接跑 `.build/release/MuM` 时没有 bundle id，
读不到已保存的项目列表。

### 关于 `.mumenv`

构建脚本会 `source .mumenv`，它只做一件事：**把 clang / SwiftPM 的模块缓存重定向到 `.build/`**。

必需的理由很硬：clang 默认把模块缓存写到 `$TMPDIR` 下的
`/var/folders/.../C/clang/ModuleCache`，而受限沙箱不让写那里，构建会直接失败：

```
error: unable to open output file '.../ModuleCache/.../SwiftShims-....pcm'
       'Operation not permitted'
```

它**不重定向 `HOME`**，这是踩过三次坑之后才定下来的。早先有一行
`export HOME="$PWD/.build/home"`，看起来无害，实际会让所有读 `~/.gitconfig`、
`~/.config/gh`、`~/Library/Preferences` 的命令找不到配置：

| 症状 | 真实原因 |
| :--- | :--- |
| `git commit` 报 "Author identity unknown" | git 去 `.build/home` 找 `.gitconfig` |
| `gh` 报 "please run gh auth login" | gh 去 `.build/home` 找配置 |
| 离屏快照读不到已保存的项目列表 | `UserDefaults` 指向了另一个 HOME |

**三个症状和"HOME 被改"看起来都毫无关系** —— 这正是它值得单独记一笔的原因。

另外支持一个可选的 GitHub 代理（用 `GIT_CONFIG_COUNT` 注入，不改用户的 `~/.gitconfig`），
地址写在 `.mumenv.local`（已 gitignore），不硬编码进版本库。


---

## 性能基线

`MuM --bench <文件.md>` 分三段计时：

| 阶段 | 1 MB | 5 MB | 说明 |
| :--- | ---: | ---: | :--- |
| 解析 | 47 ms | 231 ms | cmark-gfm 建 AST（1MB → 3.5 万块节点，5MB → 17.4 万） |
| **渲染** | **486 ms** | **2329 ms** | AST → `NSAttributedString`（含一次内部解析） |
| 排版 | 1006 ms | 9029 ms | TextKit `ensureLayout` 全量排版 |
| 合计 | 1.54 s | 11.6 s | 对照：小文件冷启动到窗口上屏 280 ms |

### 已知问题：大文档打开慢

**实测应用本身**（不是 bench）：打开 1 MB 的 markdown 需要 **1.1 秒**
（`applyWorkspace` 占 778 ms），而小文件是 280 ms。这直接违背定位里那句"280 毫秒"。

**主因是渲染，不是排版。** 这一点是量出来的，不是推的：

- bench 里 1 MB 的渲染 = 486 ms，而应用打开时 `applyWorkspace` = 778 ms → 大头上在渲染
- 打开 `allowsNonContiguousLayout`（关掉 TextKit 的连续排版）后，打开耗时**没有变化** ——
  说明打开时并没有在做全量排版

**还没定位到渲染里具体哪一段。** 下一步应该给 `render(_:)` 加分段计时
（行内解析 / 块级分发 / 语法高亮 / 属性写入），而不是直接改代码 ——
这个项目每个错误决定都来自"先猜后改"。

样本是合成文档（标题 + 段落 + 列表 + 引用 + 代码块 + 表格按真实比例混合）。
顺带量过：**表格只占排版开销的 8%**（5 MB 含 2.9 万张表 8966 ms vs 无表 8252 ms），
瓶颈是纯文本量本身。

## 版本与更新日志

版本号遵循 [语义化版本](https://semver.org/lang/zh-CN/)，唯一来源是仓库根目录的
[`VERSION`](VERSION) —— 构建时由 `scripts/build-app.sh` 写进 `Info.plist`，只维护一处。

所有重要变更有记录，见 [CHANGELOG.md](CHANGELOG.md)（格式遵循 Keep a Changelog）。

当前版本：**0.1.0**（尚未达到 1.0 —— 定位已清晰，但 API 与设置项仍可能变动）。

## 开源

仓库当前的状态（已逐项核对）：

- **零个人信息** —— 全仓库扫过一遍，唯一一处机器相关配置（GitHub 代理地址）已移到
  `.mumenv.local`，该文件在 `.gitignore` 里。`.mumenv` 只做模块缓存重定向，与机器无关。
- **构建产物不入库** —— `.build/`、`dist/`、`Resources/AppIcon.icns`（由脚本生成）都已忽略。
- **没有 `.xcodeproj`** —— 整个应用就是 `Package.swift` + 一个 `Info.plist`。
  拉下来 `source ./.mumenv && swift build` 就能跑，不需要装 Xcode 本体。
- **唯一的第三方依赖是 `swift-markdown`**（Apple 官方），没有私有服务、没有账号、没有遥测。

### 贡献

没有插件系统，也没有配置体系 —— 这是刻意的（见上面"架构选择"那段）。
提 PR 之前建议先开个 issue 对一下方向，避免写完才发现和"阅读是目的"这条线冲突。

### 许可证

[MIT](LICENSE)。

## 目录结构

```
MuM/
├── README.md              入口（你在这里）
├── CHANGELOG.md           每个版本改了什么、为什么原来不对
├── LICENSE  VERSION       MIT；版本号唯一来源
├── Package.swift          构建定义（没有 .xcodeproj）
│
├── docs/                  所有文档
│   ├── vision.md              定位与判断标准 ← 先读这个
│   ├── roadmap.md             版本计划与验收标准
│   ├── metrics.md             指标体系（北极星：TTFR）
│   ├── collaboration.md       三方协作规则
│   ├── versions/              版本定义，每版一个文件
│   ├── performance-baseline.md
│   └── qa-log.md
│
├── Sources/MuM/           源码
│   ├── App/                   生命周期、菜单
│   ├── Core/                  文件树、工作区、设置、计时
│   ├── Markdown/              解析与渲染（含阅读主题色板）
│   ├── UI/                    窗口、三个面板、设置界面
│   └── Debug/                 自检、离屏快照、性能基线
│
├── Tests/MuMTests/        单元测试（`swift test`）
├── scripts/               构建、图标、样本生成
├── Examples/demo/         示例项目（用 MuM 打开它）
└── Resources/Info.plist   打包资源
```

### 文件放哪：一条规则

> **根目录只放"进门必看的"。其余按用途进各自的目录。**

| 类型 | 去哪 | 例子 |
| :--- | :--- | :--- |
| 门面与约定 | 根目录 | `README.md`、`CHANGELOG.md`、`LICENSE`、`VERSION` |
| 项目文档 | `docs/` | 定位、路线图、指标、协作规范 |
| 版本定义 | `docs/versions/` | `v0.4.md` |
| 可执行工具 | `scripts/` | 构建、图标生成、样本生成 |
| 源码 | `Sources/MuM/<层>/` | 按 App / Core / Markdown / UI / Debug 分层 |
| 测试 | `Tests/MuMTests/` | |
| 示例内容 | `Examples/demo/` | 被 MuM 打开的样本项目 |

**三条约束：**

1. **根目录的 `*.md` 不超过 2 个**（README + CHANGELOG）。多出来的说明该进 `docs/`。
2. **不留可重建的文件** —— 大样本、生成物用脚本产出（见 `scripts/make-bench-fixture.py`）。
3. **不留临时产物** —— `/tmp` 里的测完就删；进程用完就关（见 `docs/collaboration.md`）。

**新增文档时先问：** 它是"进门必看"吗？不是就进 `docs/`。文档变多时按**读者**分目录，
不按文件类型分。

## 已知边界

- 数学公式（KaTeX）与 Mermaid 尚未支持 —— 这两样是原生渲染路线上代价最高的部分
- 三种模式之间没有过渡动画（朴素 NSSplitView 的取舍）
- 未做 `.gitignore` 感知，文件树用的是固定噪音目录黑名单
- 单窗口单文件，没有标签页；这是刻意的取舍，但多标签对某些工作流确实更方便
- 未做代码签名与公证，仅 ad-hoc 签名，适合本机使用

`Examples/demo/` 是一个用于验证渲染的示例项目，`docs/rendering.md` 覆盖了
所有受支持的 Markdown 元素。
