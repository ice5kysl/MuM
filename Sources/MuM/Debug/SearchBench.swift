import AppKit

/// 全局搜索性能基线（v0.5 验收第 1/2/3 条的测量工具）。
///
/// 用法：`MuM --bench-search <语料目录> <查询词>`
/// 语料目录的每个**直接子目录**算一个项目（配合
/// `scripts/make-bench-fixture.py corpus <dir> <项目数> <每项目文件数>` 生成的语料）。
///
/// 报三个数，对应三条验收：
///   首个结果  —— 从发起到第一批结果回调（验收 1：≤300ms @ 10 项目/5 万文件）
///   全部扫完  —— 到完成批次（验收 2：≤5s）
///   命中条数  —— 与 `grep -ri` 对拍（验收 8：这是最看重的一条；
///   大小写不敏感是有意的语义，见 GlobalSearchEngine 单测）
enum SearchBench {

    static func run(arguments: [String]) -> Int32 {
        guard let index = arguments.firstIndex(of: "--bench-search"), index + 2 < arguments.count else {
            FileHandle.standardError.write("用法：MuM --bench-search <语料目录> <查询词>\n".data(using: .utf8)!)
            return 2
        }

        let root = URL(fileURLWithPath: arguments[index + 1])
        let query = arguments[index + 2]

        guard let children = try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles]
        ) else {
            FileHandle.standardError.write("读不到目录：\(root.path)\n".data(using: .utf8)!)
            return 1
        }
        let scopes = children
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .map { GlobalSearchEngine.Scope(root: $0, name: $0.lastPathComponent) }
        guard !scopes.isEmpty else {
            FileHandle.standardError.write("语料目录下没有项目子目录\n".data(using: .utf8)!)
            return 1
        }
        print("语料  \(root.path)：\(scopes.count) 个项目，查询「\(query)」")
        print("")

        let start = Date()
        var firstResultMS: Double?
        var hits = 0
        var fileNameHits = 0
        var summary: GlobalSearchEngine.Batch?

        let engine = GlobalSearchEngine()
        engine.search(query: query, scopes: scopes) { batch in
            if firstResultMS == nil, !batch.hits.isEmpty {
                firstResultMS = Date().timeIntervalSince(start) * 1000
            }
            hits += batch.hits.count
            fileNameHits += batch.hits.filter { $0.kind == .fileName }.count
            if batch.isFinished {
                summary = batch
            }
        }
        // 结果批次投在主队列：CLI 模式没有 NSApplication 跑 runloop，
        // 得自己转，否则批次永远到不了（信号量等待会把主线程堵死）
        while summary == nil {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }

        guard let summary else { return 1 }
        let totalMS = Date().timeIntervalSince(start) * 1000

        print(String(format: "首个结果  %8.1f ms   （验收 1：≤ 300 ms）", firstResultMS ?? -1))
        print(String(format: "全部扫完  %8.1f ms   （验收 2：≤ 5000 ms，%d 个文件）", totalMS, summary.filesScanned))
        print("命中      \(hits) 条（内容 \(hits - fileNameHits) / 文件名 \(fileNameHits)）—— 与 grep -ri 对拍（验收 8）")
        if summary.skippedLargeFiles > 0 {
            print("跳过      \(summary.skippedLargeFiles) 个超过 10MB 的文件（显式报告，不静默漏）")
        }
        if summary.isTruncated {
            print("截断      命中达到上限 \(engine.maxHits)，结果已截断")
        }
        return 0
    }
}
