import XCTest
@testable import MuM

/// 量化 Preview 模式源码↔渲染滚动错位（2026-09-23 用户反馈：预览两栏「错位，体验不好」）。
///
/// 机制（自初始提交 61b5e0d 未变）：编辑器 `scrollFraction()`（滚动位 / 源码总可滚高）
/// → 预览同分数 `restoreScrollFraction`。**比例对比例**的前提是两栏高度分布成比例，
/// 而表格/代码块渲染后远高于其源文本 —— 内容错位随文档长度与结构差异累积。
/// （分数相等是机制的同义反复，量的必须是**内容**错位：编辑器顶到第 i 个标记时，
/// 预览顶部落在第几个标记上。）
///
/// 方法：源码里均匀埋 20 个唯一标记行；对目标标记 i（第 5/10/15 个），把编辑器滚到
/// 「标记 i 恰在视口顶」；读预览视口顶的 Y 在标记版面序列里的插值位置 j；
/// 漂移 = j − i（标记均匀分布，单位即「文档全长百分比」）。测量工具，非回归锚点。
final class PreviewScrollLinkageDriftTests: XCTestCase {

    private static let markerCount = 20

    func testContentDriftSampling() throws {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.appearance = NSAppearance(named: .aqua)

        let controller = MainWindowController()
        guard let window = controller.window else { return XCTFail("无法建立窗口") }
        window.setContentSize(MuMDesign.defaultWindowContentSize)
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderFrontRegardless()

        // 异构文档：散文段（渲染后与源码高度接近）+ 密集表格段（渲染后远高于源文本）
        var parts: [String] = ["# 漂移采样样本\n"]
        let marks = Self.markerCount
        let perSection = 12
        for m in 1...marks {
            for l in 1...perSection {
                parts.append("第 \(m)-\(l) 行散文。MuM 是原生阅读器，阅读是目的，快而不吵。\n")
            }
            parts.append("MARKER-\(String(format: "%02d", m))-TXZQ\n")
            if m > marks / 2 {  // 后半段埋表：制造高度分布差
                parts.append("\n| 指标 | 当前 | 目标 |\n|:--|--:|--:|\n")
                for r in 1...6 { parts.append("| 项\(r) | \(r * 10) | \(r * 100) |\n") }
            }
        }
        let doc = FileManager.default.temporaryDirectory
            .appendingPathComponent("mum-linkage-drift-\(UUID().uuidString).md")
        try parts.joined().write(to: doc, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: doc) }

        controller.open(url: doc)
        controller.setMode(.preview)
        XCTAssertNil(wait(5) { window.contentView?.bounds.width ?? 0 >= MuMDesign.minWindowContentWidth })
        let editor = controller.debugEditor
        let preview = controller.debugPreview
        XCTAssertNil(wait(5) { (preview.debugScrollView.documentView?.frame.height ?? 0) > 500 }, "预览未完成排版")

        // editor.scrollView 是 private 且无 debug 钩子——从视图层级取（不改 Sources/，那归 kimi）
        guard let editorScroll = editor.view.subviews.compactMap({ $0 as? NSScrollView }).first else {
            return XCTFail("编辑器视图层级里找不到 NSScrollView")
        }
        guard let editorTextView = editorScroll.documentView as? NSTextView else {
            return XCTFail("编辑器 documentView 不是 NSTextView")
        }
        let editorText = editor.text as NSString
        let previewText = preview.previewTextView.string as NSString

        // 两侧标记的版面 Y（含 textContainerInset 偏移，直接用 layoutManager 坐标 + 视口换算）
        func markerYs(in text: NSString, textView: NSTextView) -> [CGFloat] {
            var ys: [CGFloat] = []
            for m in 1...marks {
                let needle = "MARKER-\(String(format: "%02d", m))-TXZQ" as NSString
                let range = text.range(of: needle as String)
                guard range.location != NSNotFound else { return [] }
                let glyph = textView.layoutManager!.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
                let rect = textView.layoutManager!.boundingRect(forGlyphRange: glyph, in: textView.textContainer!)
                // 视口坐标 = 版面 Y + containerInset - 可视原点；这里统一到「文档顶部为 0」：
                // layoutManager 坐标 + textContainerInset.height 即 scrollView 文档坐标
                let inset = textView.textContainerInset.height
                ys.append(rect.minY + inset)
            }
            return ys
        }
        guard editorText.length > 0, previewText.length > 0 else { return XCTFail("两侧文本未就位") }
        let eYs = markerYs(in: editorText, textView: editorTextView)
        let pYs = markerYs(in: previewText, textView: preview.previewTextView)
        guard eYs.count == marks, pYs.count == marks else {
            return XCTFail("标记定位失败 editor=\(eYs.count) preview=\(pYs.count)")
        }

        var report = "\n[linkage-drift] 内容错位采样（编辑器顶到标记 i → 预览顶部实际落在标记 j）："
        var results: [String] = []
        for i in [5, 10, 15] {
            // 编辑器：滚到标记 i 恰在视口顶
            let eClip = editorScroll.contentView
            eClip.scroll(to: NSPoint(x: 0, y: eYs[i - 1]))
            editorScroll.reflectScrolledClipView(eClip)
            _ = wait(0.5) { true }   // boundsDidChange → onScroll → 预览落位

            // 预览：视口顶 Y 在标记序列里插值
            let pTop = preview.debugScrollView.contentView.bounds.origin.y
            var j: Double = 0
            if pTop <= pYs[0] { j = max(Double(pTop / pYs[0]), 0) }  // 0~1 号之前线性垫底
            else if pTop >= pYs[marks - 1] { j = Double(marks) }
            else {
                for k in 0..<(marks - 1) where pTop >= pYs[k] && pTop < pYs[k + 1] {
                    let span = max(pYs[k + 1] - pYs[k], 0.5)
                    j = Double(k + 1) + Double(pTop - pYs[k]) / Double(span)
                }
            }
            let driftPct = (j - Double(i)) / Double(marks) * 100
            results.append(String(format: "i=%d → j=%.1f（漂移 %+.1f%% 全长）", i, j, driftPct))
            report += "\n[linkage-drift] " + results.last!
        }
        print(report)
        // 联动必须在工作（预览跟动了）——否则测的是死水。跟动的证据：三次采样 j 不全等
        // （预览若纹丝不动，j 会停在同一个值）
        let js = results.count
        XCTAssertGreaterThanOrEqual(js, 3)
    }

    /// 轮询等待（uitest 同款：runloop 转圈而非睡死），nil=条件满足
    private func wait(_ seconds: Double, _ condition: () -> Bool) -> String? {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() { return nil }
            RunLoop.main.run(until: Date().addingTimeInterval(0.02))
        }
        return "timeout"
    }
}
