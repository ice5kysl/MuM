# 渲染能力清单

这个文件把视觉效果最重的元素放在最前面，方便一眼检查排版。

## 表格

| 方案 | 冷启动 | 内存 | 排版能力 | 依赖体积 |
| :--- | ---: | :---: | :--- | ---: |
| 原生 NSTextView | ~50ms | ~80MB | 需自己画 | 0 |
| WKWebView | ~400ms | ~200MB | 最强 | 0 |
| Electron | ~900ms | ~350MB | 最强 | 200MB+ |
| 纯 SwiftUI Text | ~60ms | ~70MB | 极有限 | 0 |

表格需要边框、表头底色、列对齐三样同时正确才像样。

## 引用

> 第一段引用。引用块的左侧应当有一条连续的竖线，从第一段的顶端一直贯到
> 最后一段的底端 —— 中间不能因为段落间距而断开。
>
> 第二段引用，用来验证上面那句话。如果竖线在段与段之间断开，看起来就像
> 三个独立的方块，而不是一个引用。

嵌套一层：

> 外层引用
>
> > 内层引用，竖线应当出现在更靠右的位置
> >
> > 内层第二段
>
> 回到外层

## 代码块

```swift
import AppKit

/// 代码块需要：等宽字体、浅底色、左右内缩、以及内部的语法高亮。
final class MarkdownRenderer {
    private let theme: MarkdownTheme
    private let baseURL: URL?

    func render(_ markdown: String) -> NSAttributedString {
        let document = Document(parsing: markdown)   // cmark-gfm
        let output = NSMutableAttributedString()

        renderBlocks(Array(document.children), into: output, context: BlockContext())

        // 去掉尾部空行，避免滚动区底部一大片空白
        trimTrailingNewlines(output)
        return output
    }
}
```

其他语言：

```python
from dataclasses import dataclass

@dataclass
class Node:
    """语法高亮的语言表是数据驱动的。"""
    name: str
    children: list["Node"] = None  # type: ignore

    def walk(self):
        yield self
        for child in self.children or []:
            yield from child.walk()
```

```sql
SELECT workspace.path,
       COUNT(*) AS opens
  FROM events
 WHERE created_at > now() - interval '7 days'
 GROUP BY 1
 ORDER BY opens DESC
 LIMIT 10;
```

## 分隔线与任务列表

---

- [x] 标题、段落、强调
- [x] 有序 / 无序 / 嵌套列表
- [x] 任务列表
- [x] 引用（含嵌套）
- [x] 代码块 + 语法高亮
- [x] 表格
- [ ] 数学公式
- [ ] Mermaid 图

---

完。
