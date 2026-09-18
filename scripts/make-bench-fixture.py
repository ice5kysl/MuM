#!/usr/bin/env python3
"""生成 MuM 性能基线用的 Markdown 样本：混合标题/段落/代码块/列表/表格/引用。

两种用法：
  make-bench-fixture.py <MB> <out.md>                  单个大文件（渲染/TTFR 基准）
  make-bench-fixture.py corpus <outdir> <项目数> <每项目文件数>
      多项目语料（全局搜索基准，v0.5 验收 1/2/3 条）。约 5% 的文件里埋入
      稀有词 XYZZYMUM，位置由文件序号确定性决定，方便和 `grep -r` 对拍。
"""
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
    if len(sys.argv) > 1 and sys.argv[1] == "corpus":
        make_corpus(sys.argv[2], int(sys.argv[3]), int(sys.argv[4]))
        return
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


def make_corpus(outdir, projects, files_per_project):
    """全局搜索基准语料：projects 个项目 × files_per_project 个小 Markdown 文件。

    稀有词 XYZZYMUM 埋在每个项目里序号 % 20 == 0 的文件（5%）中，
    命中行号 = 3，位置完全确定 —— 对拍：
      grep -rn XYZZYMUM <outdir> | wc -l   应等于  projects * ceil(files_per_project / 20)
    """
    import os
    os.makedirs(outdir, exist_ok=True)
    planted = 0
    for p in range(projects):
        project_dir = os.path.join(outdir, f"project-{p:02d}")
        os.makedirs(project_dir, exist_ok=True)
        for f in range(files_per_project):
            lines = [
                f"# project-{p:02d} 文档 {f}",
                "",
                "这是全局搜索基准语料里的普通一段，不含任何稀有词。",
                "MuM 是 macOS 原生 Markdown 阅读器，阅读是目的。",
                "",
            ]
            if f % 20 == 0:
                # 插到第 3 行（0 起算下标 2），与上面的"第 3 行"约定一致
                lines.insert(2, f"稀有词 XYZZYMUM 埋在 project-{p:02d} 的文档 {f} 里。")
                planted += 1
            with open(os.path.join(project_dir, f"doc-{f:05d}.md"), "w", encoding="utf-8") as out:
                out.write("\n".join(lines))
    total = projects * files_per_project
    print(f"{outdir}: {projects} 项目 × {files_per_project} 文件 = {total} 个，埋词 {planted} 处")

if __name__ == "__main__":
    main()
