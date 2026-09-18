import XCTest
@testable import MuM

/// ⌘⇧F 全局搜索：结果正确性（v0.5 验收第 8 条）、二进制/大文件/符号链接的边界、
/// 取消与截断语义。正确性优先于速度 —— 搜索漏了什么比搜索慢严重得多。
final class GlobalSearchEngineTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mum-globalsearch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - 正确性（与 grep -r 对拍的语义）

    func testContentHitCarriesLineContextAndOccurrence() throws {
        let project = makeProject("alpha")
        try write("first needle here\nnothing\nsecond NEEDLE and needle again\n", at: project, "notes.md")

        let hits = run(query: "needle", scopes: [scope(project)])

        let content = hits.filter { $0.kind == .content }
        XCTAssertEqual(content.count, 3)
        XCTAssertEqual(content.map(\.lineNumber), [1, 3, 3])
        XCTAssertEqual(content.map(\.occurrence), [1, 2, 3], "occurrence 是文件内第几处命中，定位用")
        XCTAssertEqual(content[0].lineText, "first needle here")
        // 大小写不敏感
        XCTAssertEqual(content[1].lineText, "second NEEDLE and needle again")
        XCTAssertEqual(content[0].matchRangeInLine?.location, 6)
    }

    func testFileNameHit() throws {
        let project = makeProject("alpha")
        try write("no match inside\n", at: project, "needle-report.md")

        let hits = run(query: "needle", scopes: [scope(project)])
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].kind, .fileName)
        XCTAssertEqual(hits[0].relativePath, "needle-report.md")
        XCTAssertEqual(hits[0].lineNumber, 0)
    }

    func testCrossProjectScopesAndNarrowing() throws {
        let alpha = makeProject("alpha")
        let beta = makeProject("beta")
        try write("needle in alpha\n", at: alpha, "a.md")
        try write("needle in beta\n", at: beta, "b.md")

        let both = run(query: "needle", scopes: [scope(alpha), scope(beta)])
        XCTAssertEqual(Set(both.map(\.scopeIndex)), [0, 1])

        // 收窄到 beta：alpha 的命中必须消失
        let onlyBeta = run(query: "needle", scopes: [scope(beta)])
        XCTAssertEqual(onlyBeta.count, 1)
        XCTAssertEqual(onlyBeta[0].scopeIndex, 0, "只搜一个 scope 时下标相对传入数组")
        XCTAssertEqual(onlyBeta[0].relativePath, "b.md")
    }

    // MARK: - 边界：二进制 / 大文件 / 符号链接 / 忽略目录

    func testBinaryWithTextExtensionIsSkipped() throws {
        let project = makeProject("alpha")
        // 扩展名是 .md 但内容是二进制 —— 必须过 TextDecoding 的守卫（审计 D-2）
        var bytes = Data("needle ".utf8)
        bytes.append(0)
        bytes.append(Data("more needle".utf8))
        try bytes.write(to: project.appendingPathComponent("fake.md"))

        let hits = run(query: "needle", scopes: [scope(project)])
        XCTAssertTrue(hits.filter { $0.kind == .content }.isEmpty,
                      "二进制文件不得产生内容命中，否则对拍会多出 grep 没有的行")
    }

    func testGBKEncodedFileIsSearched() throws {
        let project = makeProject("alpha")
        let gb18030 = String.Encoding(
            rawValue: CFStringConvertEncodingToNSStringEncoding(
                CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let text = "中文前缀 needle 中文后缀\n"
        try text.data(using: gb18030)!.write(to: project.appendingPathComponent("gbk.txt"))

        let hits = run(query: "needle", scopes: [scope(project)])
        XCTAssertEqual(hits.count, 1)
        XCTAssertEqual(hits[0].lineText, "中文前缀 needle 中文后缀")
    }

    func testLargeFileIsSkippedAndReported() throws {
        let project = makeProject("alpha")
        try write("needle in a huge file\n", at: project, "huge.md")

        let engine = GlobalSearchEngine()
        engine.maxFileSize = 10 // 字节：任何文件都"超大"，省得真写 10MB
        let (hits, summary) = run(engine: engine, query: "needle", scopes: [scope(project)])

        XCTAssertTrue(hits.isEmpty)
        XCTAssertEqual(summary.skippedLargeFiles, 1, "跳过大文件必须显式报告，不静默漏")
    }

    func testSymlinkLoopDoesNotHangOrLeak() throws {
        let project = makeProject("alpha")
        try write("needle\n", at: project, "real.md")
        // 指回项目根的符号链接：跟随它的话扫描永远走不完
        try FileManager.default.createSymbolicLink(
            at: project.appendingPathComponent("loop"),
            withDestinationURL: project)

        let hits = run(query: "needle", scopes: [scope(project)])
        XCTAssertEqual(hits.count, 1, "符号链接不跟随（与 grep -r 对齐），命中只来自真实文件")
        XCTAssertEqual(hits[0].relativePath, "real.md")
    }

    func testIgnoredDirectoriesAreSkipped() throws {
        let project = makeProject("alpha")
        try write("needle in git internals\n", at: project, ".git/config.md")
        try write("needle in dependencies\n", at: project, "node_modules/pkg/index.md")
        try write("needle in plain sight\n", at: project, "visible.md")

        let hits = run(query: "needle", scopes: [scope(project)])
        XCTAssertEqual(hits.map(\.relativePath), ["visible.md"],
                       "与文件树同一套忽略规则：.git / node_modules 不进结果")
    }

    // MARK: - 取消与截断

    func testCancellationStopsScan() throws {
        let project = makeProject("alpha")
        for i in 0..<200 {
            try write("needle \(i)\n", at: project, "file\(i).md")
        }

        let engine = GlobalSearchEngine()
        var token: GlobalSearchEngine.Token?
        // 确定性取消：扫完第一个文件就拉闸，不等时序碰运气
        engine.onFileScannedForTesting = { token?.cancel() }

        let finished = expectation(description: "finished")
        var summary: GlobalSearchEngine.Batch?
        token = engine.search(query: "needle", scopes: [scope(project)]) { batch in
            if batch.isFinished {
                summary = batch
                finished.fulfill()
            }
        }
        waitForExpectations(timeout: 10)

        XCTAssertEqual(summary?.wasCancelled, true)
        XCTAssertLessThan(summary?.filesScanned ?? .max, 200, "取消后不该扫完全部文件")
    }

    func testTruncationAtHitCap() throws {
        let project = makeProject("alpha")
        for i in 0..<5 {
            try write("needle\n", at: project, "file\(i).md")
        }

        let engine = GlobalSearchEngine()
        engine.maxHits = 3
        let (hits, summary) = run(engine: engine, query: "needle", scopes: [scope(project)])

        XCTAssertEqual(hits.count, 3)
        XCTAssertTrue(summary.isTruncated, "命中到顶必须显式报告截断")
    }

    func testEmptyQueryFinishesImmediately() {
        let project = makeProject("alpha")
        let (hits, summary) = run(query: "  ", scopes: [scope(project)])
        XCTAssertTrue(hits.isEmpty)
        XCTAssertTrue(summary.isFinished)
        XCTAssertFalse(summary.wasCancelled)
    }

    // MARK: - 展示用上下文（结果行不能是一堵字墙）

    func testDisplayContextCollapsesWhitespace() {
        let line = "    **成本**(deepseek-chat 级，约  \\$0.0015/次)：  "
        let (text, range) = GlobalSearchEngine.displayContext(
            line: line, match: NSRange(location: 11, length: 8))
        XCTAssertEqual(text, "**成本**(deepseek-chat 级，约 \\$0.0015/次)：",
                       "行首缩进与行尾空白去掉，连续空白折叠")
        XCTAssertEqual(range.map { (text as NSString).substring(with: $0) }, "deepseek")
    }

    func testDisplayContextPicksTheRightOccurrence() {
        // 一行里多个相同命中：位置必须按下标映射搬，重搜会全高亮成第一处
        let line = "second NEEDLE and needle again"
        let second = (line as NSString).range(of: "needle", options: .backwards)
        let (text, range) = GlobalSearchEngine.displayContext(line: line, match: second)
        XCTAssertEqual(text, line)
        XCTAssertEqual(range.map { (text as NSString).substring(with: $0) }, "needle")
        XCTAssertEqual(range?.location, second.location)
    }

    func testDisplayContextWindowsLongLinesAroundMatch() {
        let line = String(repeating: "前", count: 200) + "needle" + String(repeating: "后", count: 200)
        let match = NSRange(location: 200, length: 6)
        let (text, range) = GlobalSearchEngine.displayContext(line: line, match: match, maxLength: 60)
        XCTAssertLessThan(text.count, 70, "长行要开窗，不能整行铺进列表")
        XCTAssertTrue(text.hasPrefix("…"))
        XCTAssertTrue(text.hasSuffix("…"))
        XCTAssertEqual(range.map { (text as NSString).substring(with: $0) }, "needle",
                       "开窗后命中词仍在窗口里且位置正确")
    }

    func testDisplayContextWithoutMatch() {
        let (text, range) = GlobalSearchEngine.displayContext(line: "  hello  world ", match: nil)
        XCTAssertEqual(text, "hello world")
        XCTAssertNil(range)
    }

    // MARK: - 工具

    private func makeProject(_ name: String) -> URL {
        let url = root.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func scope(_ project: URL) -> GlobalSearchEngine.Scope {
        GlobalSearchEngine.Scope(root: project, name: project.lastPathComponent)
    }

    private func write(_ text: String, at project: URL, _ relativePath: String) throws {
        let url = project.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    /// 跑一次搜索并收齐所有批次，返回（全部命中，最终批次的汇总）
    @discardableResult
    private func run(
        engine: GlobalSearchEngine = GlobalSearchEngine(),
        query: String,
        scopes: [GlobalSearchEngine.Scope]
    ) -> (hits: [GlobalSearchEngine.Hit], summary: GlobalSearchEngine.Batch) {
        let finished = expectation(description: "search finished")
        var hits: [GlobalSearchEngine.Hit] = []
        var summary: GlobalSearchEngine.Batch?
        engine.search(query: query, scopes: scopes) { batch in
            hits.append(contentsOf: batch.hits)
            if batch.isFinished {
                summary = batch
                finished.fulfill()
            }
        }
        waitForExpectations(timeout: 10)
        guard let summary else {
            XCTFail("搜索没有发出完成批次")
            fatalError("unreachable")
        }
        return (hits, summary)
    }

    /// 只关心命中的便捷版
    private func run(query: String, scopes: [GlobalSearchEngine.Scope]) -> [GlobalSearchEngine.Hit] {
        run(engine: GlobalSearchEngine(), query: query, scopes: scopes).hits
    }
}
