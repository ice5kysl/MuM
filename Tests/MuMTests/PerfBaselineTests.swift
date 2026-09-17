import AppKit
import Markdown
import XCTest
@testable import MuM

/// 大文档性能基线，口径与 `MuM --bench`（Debug/RenderBench）一致：
///
///   parse   —— cmark-gfm 建 AST
///   render  —— AST → NSAttributedString（含一次内部解析，与 RenderBench 同口径）
///   layout  —— TextKit 排版，容器宽 780，**滚动时反复发生的开销**
///
/// 文档由固定种子合成，确定性：种子不变 → 内容不变 → 数字可跨提交对比。
/// 基线数字记录在 docs/performance-baseline.md；这里的断言上限故意放宽到
/// ~10 倍预期值，只拦灾难性回归（比如意外引入 O(n²)），精细对比看基线文档。
final class PerfBaselineTests: XCTestCase {

    private static let targetBytes = 1_048_576 // 1 MB
    private static let repetitions = 3

    private var text: String!
    private var renderer: MarkdownRenderer!

    override func setUpWithError() throws {
        text = Self.syntheticDocument(targetBytes: Self.targetBytes)
        renderer = MarkdownRenderer(theme: MarkdownTheme(), baseURL: nil)
    }

    // MARK: - 三段计时

    func testParsePhase() throws {
        let median = timedMedianMS("parse") {
            _ = Document(parsing: text)
        }
        XCTAssertLessThan(median, 5_000, "1MB 解析超过 5s，疑似回归")
    }

    func testRenderPhase() throws {
        let median = timedMedianMS("render") {
            _ = renderer.render(text)
        }
        XCTAssertLessThan(median, 10_000, "1MB 渲染超过 10s，疑似回归")
    }

    func testLayoutPhase() throws {
        let attributed = renderer.render(text)

        let median = timedMedianMS("layout") {
            let storage = NSTextStorage(attributedString: attributed)
            let manager = PreviewLayoutManager()
            let container = NSTextContainer(
                size: NSSize(width: 780, height: CGFloat.greatestFiniteMagnitude))
            container.lineFragmentPadding = 0
            storage.addLayoutManager(manager)
            manager.addTextContainer(container)
            manager.ensureLayout(for: container)
        }
        XCTAssertLessThan(median, 10_000, "1MB 排版超过 10s，疑似回归")
    }

    // MARK: - 合成文档的确定性

    func testSyntheticDocumentIsDeterministic() {
        let again = Self.syntheticDocument(targetBytes: Self.targetBytes)
        XCTAssertEqual(text, again, "同一种子必须生成同一文档，否则计时不可对比")
        XCTAssertGreaterThan(text.utf8.count, Self.targetBytes / 2)
    }

    // MARK: - 计时工具

    /// 取重复次数的中位数（中位数对偶发调度毛刺不敏感）
    private func timedMedianMS(_ label: String, _ body: () -> Void) -> Double {
        var samples: [Double] = []
        for _ in 0..<Self.repetitions {
            let t = CFAbsoluteTimeGetCurrent()
            body()
            samples.append((CFAbsoluteTimeGetCurrent() - t) * 1000)
        }
        let median = samples.sorted()[samples.count / 2]
        let kb = Double(text.utf8.count) / 1024
        print(String(format: "[perf] \(label)  %.1f ms  (%.0f KB 文档, %.2f ms/KB)", median, kb, median / kb))
        return median
    }

    // MARK: - 文档生成

    /// SplitMix64：小而够用的确定性伪随机
    private struct SplitMix64 {
        private var state: UInt64
        init(seed: UInt64) { state = seed }
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        mutating func int(_ range: ClosedRange<Int>) -> Int {
            range.lowerBound + Int(next() % UInt64(range.count))
        }
        mutating func pick<T>(_ array: [T]) -> T {
            array[Int(next() % UInt64(array.count))]
        }
    }

    /// 中英混排的块级结构（标题/段落/列表/代码块/表格/引用），
    /// CJK 字形对 TextKit 排版计时有实际影响，保留它。
    private static func syntheticDocument(targetBytes: Int) -> String {
        var rng = SplitMix64(seed: 0x2026_0918)
        var out: [String] = []
        let en = ["signal", "window", "render", "layout", "buffer", "cache",
                  "fragment", "scroll", "margin", "baseline", "attribute", "queue"]
        let zh = ["排版", "渲染", "缓冲区", "滚动", "边界", "基线", "约束", "属性",
                  "队列", "快照", "折叠", "切换"]
        func word() -> String {
            rng.next() % 3 == 0 ? rng.pick(zh) : rng.pick(en)
        }
        func sentence() -> String {
            (0..<rng.int(4...14)).map { _ in word() }.joined(separator: " ") + "。"
        }

        var heading = 0
        while out.joined(separator: "\n\n").utf8.count < targetBytes {
            switch rng.int(0...9) {
            case 0:
                heading += 1
                out.append(String(repeating: "#", count: rng.int(1...4)) + " 第 \(heading) 节 · " + word())
            case 1, 2:
                out.append((0..<rng.int(3...7)).map { _ in sentence() }.joined(separator: " "))
            case 3:
                out.append((0..<rng.int(3...6)).map { _ in "- \(sentence())" }.joined(separator: "\n"))
            case 4:
                let lang = rng.pick(["swift", "bash", "json"])
                let lines = (0..<rng.int(4...10)).map { _ in
                    rng.pick(en) + rng.pick([" = ", "(", "."]) + String(rng.int(0...999))
                }
                out.append("```\(lang)\n" + lines.joined(separator: "\n") + "\n```")
            case 5:
                var table = "| 列一 | 列二 | 列三 |\n| --- | --- | --- |"
                for _ in 0..<rng.int(3...8) {
                    table += "\n| \(word()) | \(rng.int(0...99)) | \(word()) |"
                }
                out.append(table)
            case 6:
                out.append("> " + (0..<rng.int(1...3)).map { _ in sentence() }.joined(separator: " "))
            default:
                out.append(sentence())
            }
        }
        return out.joined(separator: "\n\n")
    }
}
