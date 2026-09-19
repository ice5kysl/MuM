# MuM

**阅读是目的，不是编辑的副产品。**

## 它快在哪

| | MuM |
| :--- | ---: |
| 冷启动到窗口上屏 | 280 ms |
| 5 MB 文档首屏排版 | 302 ms |
| 安装包 | 1.6 MB |

## 中文排版

标点、行距、中英混排的间距 —— **不是默认值，是量出来的**。
比如 「引号」和 "quotes" 之间的空隙，和 中文 与 Latin 之间的一样，都调过。

> 大多数 Markdown 工具把阅读当成编辑的副产品。
> `preview` 这个词本身就是证据。
>
> 项目回答的是「**我在哪**」，不是「这是什么」。

## 代码

```swift
let engine = MarkdownRenderer(theme: .paper)
let attributed = engine.render(markdown)
```

- 记忆阅读位置 —— 切文件、退出，都记得你读到哪
- ⌘F 查找 · ⌘⇧O 大纲 · ⌘⇧F 跨项目搜索
- ⌘⇧E 把这一页导出成图
