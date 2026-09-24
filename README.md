# MuM

**A reading-first Markdown engine.**
**Fast, native — for humans and agents.**
阅读优先的 Markdown 引擎 —— 快、原生，给人用，也给 agent 用。

[English](README_EN.md) ·
[**下载 macOS 版**](https://github.com/ice5kysl/MuM/releases/download/v0.7.7/MuM-0.7.7.dmg) ·
[主页](https://mum.jiker.ai) ·
[更新日志](CHANGELOG.md) ·
MIT

> 签名并公证，双击即开 —— 不需要右键绕过 Gatekeeper。
> macOS 14+ · DMG 1.6 MB

![MuM 主窗口：左侧项目与文件树，右侧排版好的 Markdown 文档](docs/images/app.png)

![MuM 渲染出来的样子：中文标题、右对齐的数字表、引用竖线、语法高亮的代码块](docs/images/hero-light.png)

*上面这张图是 MuM 自己的渲染结果 —— 用 `mum render --png` 生成的，不是截图。*

---

## 定位

- **快** —— 冷启动到窗口上屏 **~260 毫秒**（同机对拍实测），5 MB 文档滚动 **100+ fps**，
  1 MB 首屏排版 7 毫秒级。快不是优化目标，是定位本身：它必须一直是真的。
- **原生** —— 全程没有 Web 引擎，Markdown 解析成 `NSAttributedString` 后在 AppKit 里
  手写排版（引用竖线、代码块底色、GFM 表格都是手绘的）。没有 Web 进程，就没有白屏、
  没有字体回退、没有滚动不同步。
- **多项目** —— 项目同时开着好几个，`⌘1`…`⌘9` 秒切，**每个各自记得你读到哪**。
- **阅读是目的** —— 别处阅读是编辑的副产品（`preview` 这个词就是证据），MuM 反过来：
  阅读是主线，编辑是配角。

## 快速上手

```bash
./scripts/run.sh
```

1. **`⌘O` 打开一个项目文件夹** —— 可以开多个，`⌘1`…`⌘9` 切换
2. **在第 2 栏点文件** —— 默认 **Read**（渲染阅读）；顶部 `Write / Read / Preview`
   或 `⌥⌘1/2/3` 切换
3. **想改内容切到 Write** —— `⌘S` 保存，有改动的文件标题旁有个小圆点
4. **底栏齿轮** 调字号、行距、阅读主题（立即生效并记住）

想让 MuM 接管双击 `.md`，见[「设为默认编辑器」](docs/development/build.md)。

---

## 使用说明

### 项目与单文件

- **项目 = 一个文件夹**。第 1 栏并排摆着所有项目，切回去自动回到上次在读的那一篇
- **打开落单文件**（访达双击 / 拖入 / `mum 文件.md`）：进**单文件模式** —— 两栏收起、
  内容区直接读，不会把所在文件夹开成项目。打开或切回项目时两栏自动还原

### 文件管理

文件树的 `···` 菜单和右键菜单里：**新建文件（`⌘N`）/ 新建文件夹 / 重命名 / 移到废纸篓**。
`···` 菜单每个动作前有小图标。**在访达中显示**（`⇧⌘J`）旁边是**在终端中打开** ——
按 Ghostty → iTerm → 系统终端自动探测你装了的那个，深目录一键就地开终端。

### 找东西

- **`⌘P` 快速打开** —— 按名字模糊搜索项目内文件
- **`⇧⌘F` 全局搜索** —— 跨所有项目搜文件名和内容，结果边搜边出
- **`⌘F` 文档内查找**（`⌘G` / `⇧⌘G` 上下一处）；**`⇧⌘O` 文档大纲** 按标题跳转
- **`⌘[` / `⌘]`** 阅读历史里后退 / 前进

### 读什么格式

| 格式 | 怎么呈现 |
| :--- | :--- |
| Markdown | 渲染排版（标题、列表、任务、引用、表格、代码高亮、本地图片、行内 HTML 白名单） |
| 代码（swift/py/js…） | 整篇语法高亮 |
| 纯文本（txt/log/字幕 srt/ass/ssa/vtt…） | 等宽排版；GBK 编码自动识别 |
| CSV / TSV | 按表格渲染（编辑时仍是原文） |
| RTF | 富文本渲染（只读） |
| 图片 / PDF | 原生查看器 |
| Office / 压缩包 / 音视频 | 不打算支持 —— 给「用默认应用打开 / 在访达中显示」导向页 |

### 导出与更新

- **`⌘⇧E` 导出** —— 正文渲染成 PNG 长图或分页 PDF（矢量，文字可选中）。
  文档里的分页指令（`<div style="page-break-after: always">` 这类）导出 PDF 时真正分页
- **自动更新** —— 新版本提示条上点「下载更新」，app 内下载 DMG、自动挂载安装盘，
  拖进「应用程序」替换即可

### 全部快捷键

| 动作 | 快捷键 |
| :--- | :--- |
| 打开项目 | `⌘O` |
| 切换到第 N 个项目 | `⌘1` … `⌘9` |
| 上一个 / 下一个项目 | `⇧⌘[` / `⇧⌘]` |
| 移动当前项目的位置 | `⌥⌘[` / `⌥⌘]` |
| 关闭当前项目 | `⇧⌘W` |
| 新建文件 | `⌘N` |
| 快速打开 | `⌘P` |
| 全局搜索 | `⇧⌘F` |
| 文档内查找 / 大纲 | `⌘F` / `⇧⌘O` |
| 上一篇 / 下一篇 | `⌘[` / `⌘]` |
| 保存 / 重新载入 | `⌘S` / `⌘R` |
| 关闭当前文件 | `⌘W` |
| 导出 | `⇧⌘E` |
| 刷新文件树 | `⇧⌘R` |
| 在访达中显示 | `⇧⌘J` |
| 显示 / 隐藏项目列表、目录树 | `⌘0` / `⌥⌘0` |
| Write / Read / Preview | `⌥⌘1` / `⌥⌘2` / `⌥⌘3` |
| 预览字号 | `⌘+` / `⌘-` |
| 全屏幕 | `⌃⌘F` |

编辑器行为：`Tab` 插入两个空格；列表项里回车自动延续标记（有序列表序号递增）；
空列表项上回车退出列表。

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

给 agent「读 markdown」是商品（cmark 免费，谁都能做）；**给 agent「排一张好版」不是**。
导出（`⌘⇧E`）和 CLI 共用同一个渲染入口 —— 人在窗口里看到的和 agent 拿到的逐像素一致。

软链进 PATH：`ln -sf /Applications/MuM.app/Contents/Resources/mum /usr/local/bin/mum`

---

## 和同类的关系

|  | 品类 | MuM 的位置 |
| :--- | :--- | :--- |
| Clearly | Mac/iOS 的 Markdown 编辑器（多端同步） | 不做移动端 |
| Lineform | 阅读优化的 Markdown 应用 | 同样认真做排版，但 MuM 是**快 + 原生**打头 |
| Obsidian | 知识库（双链） | 不做知识管理 |
| VS Code / Sublime | 代码编辑器（可扩展） | 不做插件生态 |
| **MuM** | **多项目 Markdown 阅读器** | **快 + 原生**，这条线目前是空的 |

---

## 文档

| 想了解 | 去哪 |
| :--- | :--- |
| 定位、判断标准、明确不做 | [docs/vision.md](docs/vision.md) |
| 技术选型（为什么不用 Web 引擎…） | [docs/design/technical-choices.md](docs/design/technical-choices.md) |
| 构建、测试、发布 | [docs/development/build.md](docs/development/build.md) |
| 已知边界 | [docs/known-limits.md](docs/known-limits.md) |
| 全部文档索引 | [docs/README.md](docs/README.md) |

## 反馈

**MuM 还很早。你最值钱的反馈不是"缺什么功能"，是"我卡在哪了"。**

→ [**提交反馈 / 报一个问题**](https://github.com/ice5kysl/MuM/issues/new/choose)

**涉及文件内容被改坏或丢失的，请在标题里写明** —— 最高优先级，立刻处理。

## 开源

- **零个人信息**、构建产物不入库、没有 `.xcodeproj` —— `source ./.mumenv && swift build` 就能跑
- **唯一的第三方依赖是 `swift-markdown`**（Apple 官方）；没有私有服务、没有账号、没有遥测
- 提 PR 之前建议先开 issue 对一下方向（没有插件系统和配置体系，这是刻意的）

许可证：[MIT](LICENSE)。
