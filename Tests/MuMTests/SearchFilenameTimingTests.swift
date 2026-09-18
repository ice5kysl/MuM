import XCTest
@testable import MuM

/// v0.5 验收第 3 条（文件名搜索 ≤ 200ms 出全部）的测量（cc，2026-09-19）。
///
/// 背景：kimi 的实现是**统一单遍扫描**——文件名命中与全文命中混在同一条流里，
/// 没有独立的「只搜文件名」快路径。因此本条按字面量不到：第 N 个项目的文件名
/// 命中要等枚举推进到该项目才出现。这里量的是**最后一个文件名命中的到达时刻**，
/// 给 dsh 判定「口径要不要改 / 要不要补快路径」用。
///
/// 语料与验收 1/2/8 同一份（10 项目 × 5000 文件）：
///
/// ```bash
/// python3 scripts/make-bench-fixture.py corpus /tmp/mum-corpus 10 5000
/// MUM_SEARCH_BENCH=1 swift test --filter SearchFilenameTimingTests
/// ```
///
/// 双条件才跑：语料存在 **且** `MUM_SEARCH_BENCH=1`——默认（含 accept.sh / CI）
/// 跳过。这是测量工具，不是回归锚点，不该让验收链路依赖 /tmp 状态；
/// 文件名命中的**正确性**断言在 GlobalSearchEngineTests。
final class SearchFilenameTimingTests: XCTestCase {

    private static let corpusRoot = URL(fileURLWithPath: "/tmp/mum-corpus")
    private static let query = "doc-02500"   // 每个项目恰好一个文件名命中；正文不含

    func testLastFileNameHitArrivalTiming() throws {
        // 跳过判定必须在碰磁盘之前：语料不存在时 makeScopes 会 throw，
        // 那会让"跳过"变成"失败"（kimi 2026-09-19 清理批次踩到）
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["MUM_SEARCH_BENCH"] == "1",
            "测量默认跳过：需 MUM_SEARCH_BENCH=1（见文件头注释）")
        let scopes = (try? Self.makeScopes()) ?? []
        try XCTSkipUnless(!scopes.isEmpty, "测量默认跳过：语料不存在（见文件头注释）")

        let engine = GlobalSearchEngine()
        let start = CFAbsoluteTimeGetCurrent()
        let finished = expectation(description: "search finished")

        var fileNameHitTimes: [CFAbsoluteTime] = []   // 每个文件名命中到达的时刻（相对 start）
        var firstResultMS: Double?
        var summary: GlobalSearchEngine.Batch?

        engine.search(query: Self.query, scopes: scopes) { batch in
            if firstResultMS == nil, !batch.hits.isEmpty {
                firstResultMS = (CFAbsoluteTimeGetCurrent() - start) * 1000
            }
            for hit in batch.hits where hit.kind == .fileName {
                fileNameHitTimes.append((CFAbsoluteTimeGetCurrent() - start) * 1000)
            }
            if batch.isFinished {
                summary = batch
                finished.fulfill()
            }
        }
        waitForExpectations(timeout: 30)

        guard let summary else {
            XCTFail("搜索没有发出完成批次")
            return
        }
        let totalMS = (CFAbsoluteTimeGetCurrent() - start) * 1000

        // 正确性部分（这部分才算断言）：10 个项目各命中一个文件名、零内容命中
        XCTAssertEqual(fileNameHitTimes.count, scopes.count, "每个项目应恰好一条文件名命中")
        let contentHits = summary.hits.filter { $0.kind == .content }
        XCTAssertTrue(contentHits.isEmpty, "语料正文不含 doc-02500，不应有内容命中")

        // 测量部分（打印判定数据，不断言 200ms —— 口径本身待 dsh 判定）
        print("[bench-search-filename] 首个结果        \(String(format: "%7.1f", firstResultMS ?? -1)) ms")
        let lastFileNameMS = fileNameHitTimes.max() ?? -1
        print("[bench-search-filename] 最后一个文件名命中 \(String(format: "%7.1f", lastFileNameMS)) ms   （验收 3 字面：≤ 200 ms）")
        print("[bench-search-filename] 全部扫完        \(String(format: "%7.1f", totalMS)) ms   (\(summary.filesScanned) 个文件)")
    }

    private static func makeScopes() throws -> [GlobalSearchEngine.Scope] {
        let children = try FileManager.default.contentsOfDirectory(
            at: corpusRoot, includingPropertiesForKeys: [.isDirectoryKey])
        return children
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { GlobalSearchEngine.Scope(root: $0, name: $0.lastPathComponent) }
    }
}
