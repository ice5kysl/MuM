import Foundation

/// 渲染分段计时：`render(_:)` 内部各阶段的累计耗时。
///
/// 只在 `MUM_RENDER_TIMING=1`（或 `--bench`，它会强制打开）时工作 ——
/// 平时连一次 Date() 都不多做。大文档打开慢的主因在渲染，但"渲染里哪一段慢"
/// 必须量出来：这个项目每个错误决定都来自"先猜后改"。
enum RenderProfiler {

    enum Segment: String, CaseIterable {
        case parse = "内部解析"     // render(_:) 里的 Document(parsing:)
        case highlight = "语法高亮" // CodeHighlighter.highlight 累计
        case tables = "表格"        // renderTable 累计（含单元格内的行内）
        case inlines = "行内解析"   // 块内行内序列（不含表格单元格里的）
        case images = "图片"        // NSImage 加载
    }

    static var enabled = ProcessInfo.processInfo.environment["MUM_RENDER_TIMING"] != nil

    private static var totals: [Segment: (ms: Double, count: Int)] = [:]
    /// 表格单元格里的行内时间归表格段，不重复计进「行内解析」
    private static var inTable = false

    static func reset() {
        totals = [:]
        inTable = false
    }

    /// 计时执行一段代码。未启用时零开销直穿。
    static func time<T>(_ segment: Segment, _ body: () -> T) -> T {
        guard enabled else { return body() }

        if segment == .inlines, inTable { return body() }
        if segment == .tables {
            let wasInTable = inTable
            inTable = true
            defer { inTable = wasInTable }
        }

        let t0 = Date()
        let result = body()
        let ms = Date().timeIntervalSince(t0) * 1000
        var entry = totals[segment] ?? (0, 0)
        entry.ms += ms
        entry.count += 1
        totals[segment] = entry
        return result
    }

    /// 渲染结束后打印分段报告（stderr），并给出未被任何段覆盖的"其他"。
    static func report(totalMS: Double) {
        guard enabled else { return }
        var accounted = 0.0
        var lines = "[渲染] 分段计时（累计）：\n"
        for segment in Segment.allCases {
            guard let entry = totals[segment], entry.count > 0 else { continue }
            accounted += entry.ms
            lines += String(format: "[渲染]   %@ %10.1f ms（%d 次）\n", segment.rawValue, entry.ms, entry.count)
        }
        lines += String(format: "[渲染]   %@ %10.1f ms\n", "其他（块级分发/属性拼接）", max(totalMS - accounted, 0))
        FileHandle.standardError.write(lines.data(using: .utf8)!)
    }
}
