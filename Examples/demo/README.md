# MuM 渲染自检

这份文档用来验证预览区的每一类 Markdown 元素。左边改，右边应当立刻跟着变。

## 一、标题层级

### 三级标题
#### 四级标题
##### 五级标题
###### 六级标题

## 二、行内样式

普通文本、**粗体**、*斜体*、***粗斜体***、~~删除线~~、`行内代码`。

链接： [Ghostty 官网](https://ghostty.org) · 相对链接： [设计说明](../NOTE.md)

中文排版测试：标点挤压、行高、字重是否协调。MacBook Pro 的 Retina 屏上，
正文 15pt、行距 4pt 是长时间阅读比较舒服的组合。

## 三、列表

无序列表：

- 第一项，这一行故意写得长一些，用来验证换行之后是否保持悬挂缩进对齐
- 第二项
  - 嵌套一层
  - 再嵌套
    - 第三层，符号应当自动换成方块
- 第三项

有序列表：

1. 解析 Markdown 为 AST
2. 遍历 AST 构造 `NSAttributedString`
3. 交给 `NSTextView` 渲染
4. 全程不离开进程

任务列表：

- [x] 原生渲染，不引入 Web 视图
- [x] FSEvents 监听文件变化
- [ ] 行内图片与数学公式
- [ ] 导出 PDF

## 四、引用

> 简单是可靠的前提。
> —— Edsger W. Dijkstra
>
> 引用块可以有多段，左边应当有一条连续的竖线。

嵌套引用：

> 外层引用
> > 内层引用，缩进应当再深一级

## 五、代码

行内 `let x = 42` 之后是代码块：

```swift
/// 渲染器入口：Markdown 字符串进，富文本出。
final class MarkdownRenderer {
    private let theme: MarkdownTheme
    private let baseURL: URL?

    init(theme: MarkdownTheme, baseURL: URL?) {
        self.theme = theme
        self.baseURL = baseURL
    }

    func render(_ markdown: String) -> NSAttributedString {
        let document = Document(parsing: markdown)
        let output = NSMutableAttributedString()
        renderBlocks(Array(document.children), into: output, context: BlockContext())
        return output
    }
}
```

```python
def fib(n: int) -> int:
    """朴素递归，故意写得慢一点。"""
    if n < 2:
        return n
    return fib(n - 1) + fib(n - 2)

print([fib(i) for i in range(10)])  # noqa: T201
```

```bash
# 构建并运行
./scripts/build-app.sh release
open dist/MuM.app
```

```json
{
  "name": "MuM",
  "stack": "Swift + AppKit",
  "preview": "native",
  "weight": "2.4MB"
}
```

## 六、表格

| 方案 | 冷启动 | 内存 | 排版能力 |
| :--- | ---: | :---: | :--- |
| 原生 NSTextView | ~50ms | ~80MB | 需自己画 |
| WKWebView | ~400ms | ~200MB | 最强 |
| Electron | ~900ms | ~350MB | 最强 |

## 七、分隔线

---

分隔线之上和之下都应当有留白。

## 八、图片

![这是一张不存在的图片，应当降级为占位符](images/not-found.png)

## 九、HTML

<details>
<summary>原生 HTML 块</summary>
这里应当以等宽字体原样显示。
</details>

---

最后一行。
