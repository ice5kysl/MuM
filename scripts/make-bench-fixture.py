#!/usr/bin/env python3
"""生成 MuM 性能基线用的 Markdown 样本：混合标题/段落/代码块/列表/表格/引用。"""
import sys

UNIT = """## 第 {i} 节：阅读体验与排版细节

MuM 是一个 macOS 原生的 Markdown 阅读器，**阅读是目的**，不是编辑的副产品。
它用 cmark-gfm 把文档解析成 AST，再渲染成 `NSAttributedString`，排版与绘制全部在
AppKit 里手写完成 —— 没有 Web 引擎，就没有白屏、字体回退和滚动不同步。

### {i}.1 背景与动机

在别处，阅读是编辑的副产品；`preview` 这个词本身就是证据。MuM 反过来。
一个声称"阅读是目的"的应用，连"你上次读到哪"都不记得，这句话就是空的。

```swift
// 第 {i} 节示例代码：恢复阅读位置
func restoreScrollPosition(for url: URL) {{
    guard let fraction = store.scrollFraction(for: url) else {{ return }}
    let visibleHeight = scrollView.documentVisibleRect.height
    let y = fraction * (documentHeight - visibleHeight)
    scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
}}
```

- 快：冷启动到窗口上屏 280ms，**这是定位的命根子**
- 原生：2.8MB，全程 AppKit，无 `WKWebView`
- 多项目：`⌘1`…`⌘9` 秒切，项目是主语

| 指标 | 当前 | 目标 | 怎么量 |
| :--- | ---: | ---: | :--- |
| 冷启动到上屏 | 280 ms | ≤ 300 ms | `MUM_LAUNCH_TIMING=1` |
| 1 MB 打开 | 1100 ms | ≤ 400 ms | `applyWorkspace` 分段 |
| 渲染自检 | 24/24 | 全绿 | `--selftest` |

> 测量，不要推理。当你发现自己在推理渲染结果而不是测量它的时候，
> 停下来写个测量工具。这个项目每个错误决定都来自"先猜后改"。

"""

def main():
    target_mb = float(sys.argv[1])
    out_path = sys.argv[2]
    target = int(target_mb * 1024 * 1024)
    parts = ["# MuM 性能基线样本\n\n"]
    size = len(parts[0].encode("utf-8"))
    i = 0
    while size < target:
        i += 1
        chunk = UNIT.format(i=i)
        parts.append(chunk)
        size += len(chunk.encode("utf-8"))
    with open(out_path, "w", encoding="utf-8") as f:
        f.write("".join(parts))
    print(f"{out_path}: {size/1024/1024:.2f} MB, {i} 节")

if __name__ == "__main__":
    main()
