# MuM

**A reading-first Markdown engine.**
**Fast, native — for humans and agents.**
阅读优先的 Markdown 引擎 —— 快、原生，给人用，也给 agent 用。

[**下载 macOS 版**](https://github.com/ice5kysl/MuM/releases/download/v0.6.0/MuM-0.6.0.dmg) ·
[主页](https://mum.jiker.ai) ·
[更新日志](CHANGELOG.md) ·
MIT

> 签名并公证，双击即开 —— 不需要右键绕过 Gatekeeper。
> macOS 14+ · 1.6 MB

![MuM 主窗口：左侧项目与文件树，右侧排版好的 Markdown 文档](docs/images/app.png)

![MuM 渲染出来的样子：中文标题、右对齐的数字表、引用竖线、语法高亮的代码块](docs/images/hero-light.png)

*上面这张图是 MuM 自己的渲染结果 —— 用 `mum render --png` 生成的，不是截图。*

---

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

**Native.** 3.4 MB，全程没有 Web 引擎 —— Markdown 走 cmark-gfm 解析成 `NSAttributedString`，
排版和绘制都在 AppKit 里自己写。这不是性能优化，是**架构选择**：没有 Web 进程，就没有
白屏、没有字体回退、没有滚动不同步。代价是每个排版效果都得自己实现（引用块竖线、
分隔线、代码块底色、GFM 表格都是手绘的）。

**Multi-project.** 项目是主语。大多数 Markdown 应用一次只装一个文件夹，MuM 同时开着多个，
`⌘1`…`⌘9` 秒切 —— 因为项目回答的是"**我在哪**"，而大多数编辑器只回答"这是什么"。

**Reading is the point.** 这一句是界限。在别处，阅读是编辑的副产品 —— `preview` 这个词本身
就是证据，它暗示"真正的工作是写，看只是顺便"。MuM 反过来：阅读是目的，编辑只是偶尔需要。
上面三句都是为它服务的 —— 快是为了读的时候不被打断，原生渲染是为了读得舒服，
多项目是为了知道自己在哪读。

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

## 功能

- **切换即恢复现场** —— 切回某个项目时自动回到上次在读的那一篇，没有记录则打开 README
- **文件过滤** —— 按文件名递归搜索，带目录预算，超大仓库里也不会卡住界面
- **实时预览** —— 编辑区改动 110ms 后重排预览；并排模式下按比例联动滚动
- **渲染支持** —— 标题、行内样式、嵌套列表、任务列表、引用（含嵌套）、
  代码块语法高亮、GFM 表格、分隔线、本地图片
- **非文本预览** —— 图片、PDF 走原生查看器；RTF 按富文本渲染（只读）；
  CSV / TSV 按表格渲染；代码文件整篇语法高亮
- **不支持的格式给去处** —— Office 文档、压缩包、音视频这类不在计划里的格式，
  占位页直接给「用默认应用打开」和「在访达中显示」
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

## 给 agent 用

**同一个引擎，第二个出口。** 无窗口、无 Dock 图标、无 UI 激活：

```bash
mum render doc.md --png out.png --theme paper --dark   # 无窗口出图
mum render doc.md --pdf out.pdf
mum outline doc.md --json                              # 标题树
mum search 关键词 --json                                # 跨项目搜索
mum check  doc.md --json                               # 退出码有意义
```

**为什么这条腿站得住**：给 agent「读 markdown」是商品 —— cmark-gfm 免费，
谁都能做。**给 agent「排一张好版」不是** —— 那需要一套手写排版引擎，
而我们有（无 Web 引擎，CJK 间距、阅读主题全是实测调过的）。

导出（`⌘⇧E`）和 CLI **共用同一个正文渲染入口** —— 同一篇文档，
人在窗口里看到的和 agent 拿到的图逐像素一致。

---

## 文档

| 想了解 | 去哪 |
| :--- | :--- |
| **为什么是这个定位**、判断标准、明确不做 | [docs/vision.md](docs/vision.md) |
| 每个版本做什么、验收标准 | [docs/roadmap.md](docs/roadmap.md) · [docs/versions/](docs/versions/) |
| 指标体系（北极星 TTFR） | [docs/metrics.md](docs/metrics.md) |
| **现在到哪一步了** | [docs/status.md](docs/status.md) |
| 技术选型（为什么不用 Web 引擎…） | [docs/design/technical-choices.md](docs/design/technical-choices.md) |
| 界面与交互 | [docs/design/interface.md](docs/design/interface.md) |
| 构建、测试、发布 | [docs/development/build.md](docs/development/build.md) |
| 仓库结构 | [docs/development/layout.md](docs/development/layout.md) |
| 性能基线怎么量的 | [docs/perf/](docs/perf/) |
| 已知边界 | [docs/known-limits.md](docs/known-limits.md) |
| 全部文档索引 | [docs/README.md](docs/README.md) |

---

## 反馈

**MuM 还很早。你最值钱的反馈不是"缺什么功能"，是"我卡在哪了"。**

→ [**提交反馈 / 报一个问题**](https://github.com/ice5kysl/MuM/issues/new/choose)

表格里会问你三件事：**打开它第一个动作是什么 · 哪里停顿超过 5 秒 ·
脑子里问了什么问题**。**第三条最有用** —— 那说明界面上没说清。

**涉及文件内容被改坏或丢失的，请在标题里写明** —— 最高优先级，我们立刻处理。

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
