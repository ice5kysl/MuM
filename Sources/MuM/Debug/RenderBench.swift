import AppKit
import Markdown

/// 大文档性能基线。
///
/// 分三段计时，因为它们的代价来源完全不同：
///   parse   —— cmark-gfm 建 AST
///   render  —— AST → NSAttributedString（含一次内部解析）
///   layout  —— TextKit 排版，**这才是滚动时真正反复发生的开销**
///
/// 只看 render 会给人错觉：它不含排版，而用户滚动时卡不卡由 layout 决定。
enum RenderBench {

    static func run(arguments: [String]) -> Int32 {
        guard let index = arguments.firstIndex(of: "--bench"), index + 1 < arguments.count else {
            FileHandle.standardError.write("用法：MuM --bench <文件.md>\n".data(using: .utf8)!)
            return 2
        }

        let path = arguments[index + 1]
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
            FileHandle.standardError.write("读不到文件：\(path)\n".data(using: .utf8)!)
            return 1
        }

        let mb = Double(text.utf8.count) / 1_048_576
        let label = (path as NSString).lastPathComponent
        print("文件  \(label)")
        print("大小  \(String(format: "%.2f", mb)) MB / \(text.count) 字符 / \(text.split(separator: "\n").count) 行")
        print("")

        // 1) 解析
        let t0 = Date()
        let document = Document(parsing: text)
        let parseMS = Date().timeIntervalSince(t0) * 1000
        let blockCount = countBlocks(document)
        print(String(format: "解析   %8.1f ms   AST 里 %d 个块级节点", parseMS, blockCount))

        // 2) 渲染
        let theme = MarkdownTheme()
        let renderer = MarkdownRenderer(
            theme: theme,
            baseURL: URL(fileURLWithPath: path).deletingLastPathComponent()
        )
        RenderProfiler.enabled = true
        RenderProfiler.reset()
        let t1 = Date()
        let attributed = renderer.render(text)
        let renderMS = Date().timeIntervalSince(t1) * 1000
        print(String(format: "渲染   %8.1f ms   → %d 字符的富文本（含一次内部解析）", renderMS, attributed.length))

        // 3) 排版 —— 用户滚动时反复发生的开销
        let storage = NSTextStorage(attributedString: attributed)
        let manager = PreviewLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 780, height: CGFloat.greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        storage.addLayoutManager(manager)
        manager.addTextContainer(container)

        let t2 = Date()
        manager.ensureLayout(for: container)
        let layoutMS = Date().timeIntervalSince(t2) * 1000
        let used = manager.usedRect(for: container)
        print(String(format: "排版   %8.1f ms   文档高 %.0f pt", layoutMS, used.height))

        print("")
        print(String(format: "合计   %8.1f ms", parseMS + renderMS + layoutMS))
        print("（对照：MuM 冷启动到窗口上屏 280ms。渲染层是用户滚动时才感受到的那部分。）")
        return 0
    }

    private static func countBlocks(_ markup: Markup) -> Int {
        var count = 1
        for child in markup.children { count += countBlocks(child) }
        return count
    }
}
