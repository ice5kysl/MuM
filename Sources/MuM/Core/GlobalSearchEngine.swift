import Foundation

/// ⌘⇧F 全局搜索：跨所有已打开项目的文件名 + 全文搜索。
///
/// 关键取舍（v0.5 定义）：**不建索引，按需搜**。没有后台常驻线程，不碰冷启动；
/// 代价是慢，但配合流式结果 + 可中止，体感是"立刻有东西"。
///
/// 正确性优先于速度：搜索漏了什么比搜索慢严重得多。因此扫描规则刻意与
/// `grep -r` 对齐，方便对拍 —— 不跟随符号链接（grep -R 才跟）、文本判定复用
/// TextDecoding 的二进制守卫（审计 D-2），超过大小上限的文件**显式报告跳过**，
/// 不静默漏。
final class GlobalSearchEngine {

    /// 一个搜索范围：一个打开的项目
    struct Scope {
        let root: URL
        let name: String
    }

    /// 一条命中。文件名命中没有行号与上下文（lineNumber == 0）。
    struct Hit {
        enum Kind {
            case fileName
            case content
        }
        /// 命中文件属于 scopes 里的哪一个（面板按它显示项目名、决定要不要切项目）
        let scopeIndex: Int
        let fileURL: URL
        /// 相对项目根的路径
        let relativePath: String
        let kind: Kind
        /// 1 起算；文件名命中为 0
        let lineNumber: Int
        /// 命中行全文（去掉行尾换行）；文件名命中为空
        let lineText: String
        /// 命中词在 lineText 里的位置（UTF-16 偏移）；文件名命中为 nil
        let matchRangeInLine: NSRange?
        /// 这是该文件里第几处内容命中（1 起算），点结果定位用；文件名命中为 0
        let occurrence: Int
    }

    /// 一批流式结果。isFinished 的那一批是最后一批，携带汇总信息。
    struct Batch {
        let hits: [Hit]
        let filesScanned: Int
        /// 因超过大小上限被跳过的文件数（在结果里显式说明，不静默漏）
        let skippedLargeFiles: Int
        let isFinished: Bool
        let wasCancelled: Bool
        /// 命中数达到上限被截断 —— 用户该把查询写得更具体
        let isTruncated: Bool
    }

    final class Token {
        private let lock = NSLock()
        private var _cancelled = false

        func cancel() {
            lock.lock()
            _cancelled = true
            lock.unlock()
        }

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            return _cancelled
        }
    }

    /// 超过这个大小的文件不做全文搜索（性能陷阱），但会计入 skippedLargeFiles 显式报告
    var maxFileSize = 10 * 1024 * 1024
    /// 命中总数上限：常见词在 5 万文件里能炸出几十万条，列表本身先垮
    var maxHits = 10_000

    /// 测试钩子：每扫完一个文件在后台线程调一次。单测用它实现确定性的中途取消。
    var onFileScannedForTesting: (() -> Void)?

    /// 开始一次搜索。结果分批在主线程回调；上一批没扫完也可以 cancel。
    /// 扫描在后台串行进行 —— 瓶颈是磁盘 IO，并发只会争抢，还引入顺序不确定性。
    @discardableResult
    func search(
        query rawQuery: String,
        scopes: [Scope],
        onBatch: @escaping (Batch) -> Void
    ) -> Token {
        let token = Token()
        let query = rawQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !scopes.isEmpty else {
            DispatchQueue.main.async {
                onBatch(Batch(hits: [], filesScanned: 0, skippedLargeFiles: 0,
                              isFinished: true, wasCancelled: false, isTruncated: false))
            }
            return token
        }

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            run(query: query, scopes: scopes, token: token, onBatch: onBatch)
        }
        return token
    }

    // MARK: - 扫描（后台线程）

    private func run(
        query: String,
        scopes: [Scope],
        token: Token,
        onBatch: @escaping (Batch) -> Void
    ) {
        var pending: [Hit] = []
        var filesScanned = 0
        var skippedLarge = 0
        var totalHits = 0
        var truncated = false
        var lastFlush = CFAbsoluteTimeGetCurrent()

        func emitBatch(isFinished: Bool) {
            let batch = Batch(
                hits: pending,
                filesScanned: filesScanned,
                skippedLargeFiles: skippedLarge,
                isFinished: isFinished,
                wasCancelled: token.isCancelled,
                isTruncated: truncated
            )
            pending = []
            DispatchQueue.main.async { onBatch(batch) }
        }

        for (scopeIndex, scope) in scopes.enumerated() {
            if token.isCancelled || truncated { break }

            guard let enumerator = FileManager.default.enumerator(
                at: scope.root,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey],
                options: [.skipsPackageDescendants]
            ) else { continue }

            let rootPath = scope.root.path + "/"

            for case let url as URL in enumerator {
                if token.isCancelled { break }

                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey])

                // 符号链接一律不跟：与 grep -r 对齐（对拍的基准），也天然防环
                if values?.isSymbolicLink == true {
                    if values?.isDirectory == true { enumerator.skipDescendants() }
                    continue
                }

                if FileTreeLoader.shouldIgnore(url: url) {
                    if values?.isDirectory == true { enumerator.skipDescendants() }
                    continue
                }
                guard values?.isDirectory == false else { continue }

                filesScanned += 1

                let path = url.path
                let relative = path.hasPrefix(rootPath)
                    ? String(path.dropFirst(rootPath.count))
                    : url.lastPathComponent

                // 文件名匹配：子串、大小写不敏感。不用模糊匹配 —— 全局搜索要的是
                // 可预期（和 grep 一致的"所见即所得"），模糊打分是 ⌘P 的场景。
                if url.lastPathComponent.range(of: query, options: .caseInsensitive) != nil {
                    pending.append(Hit(
                        scopeIndex: scopeIndex, fileURL: url, relativePath: relative,
                        kind: .fileName, lineNumber: 0, lineText: "",
                        matchRangeInLine: nil, occurrence: 0
                    ))
                    totalHits += 1
                }

                // 全文匹配。非文本（图片/PDF/未知格式）不读 —— 与文件树的呈现一致；
                // 文本判定内部的二进制守卫（NUL 字节、控制字符嗅探）兜底扩展名撒谎的情况。
                let kind = FileKind(url: url, isDirectory: false)
                if kind.isTextual {
                    if let size = values?.fileSize, size > maxFileSize {
                        skippedLarge += 1
                    } else if let decoded = TextDecoding.decode(url: url) {
                        totalHits += scanContent(
                            decoded.text, query: query,
                            scopeIndex: scopeIndex, fileURL: url, relativePath: relative,
                            into: &pending, token: token,
                            remaining: maxHits - totalHits
                        )
                    }
                }

                onFileScannedForTesting?()

                if totalHits >= maxHits { truncated = true }

                // 流式节流：攒够 50 条或距上批超过 40ms 就发一次 —
                // 首结果要快（≤300ms 的验收就压在这里），也不能用主线程洪水淹没 UI
                let now = CFAbsoluteTimeGetCurrent()
                if !pending.isEmpty, pending.count >= 50 || now - lastFlush > 0.04 {
                    lastFlush = now
                    emitBatch(isFinished: false)
                }

                if truncated { break }
            }
        }

        emitBatch(isFinished: true)
    }

    /// 在一份已解码的文本里找所有命中，追加到 pending。返回新增的命中数。
    ///
    /// 不在无命中时切行：绝大多数文件一个命中都没有，逐行拆字符串是纯浪费。
    /// 命中的行号用递增扫描算 —— 命中位置天然升序，换行计数从上一次位置接着数，
    /// 总开销是 O(文件) 而不是 O(命中数 × 文件)。
    private func scanContent(
        _ text: String,
        query: String,
        scopeIndex: Int,
        fileURL: URL,
        relativePath: String,
        into pending: inout [Hit],
        token: Token,
        remaining: Int
    ) -> Int {
        let haystack = text as NSString
        var found = 0
        var searchRange = NSRange(location: 0, length: haystack.length)
        var lineNumber = 1
        var newlineCountedUpTo = 0

        while searchRange.length > 0, found < remaining {
            if found % 256 == 0, token.isCancelled { break }

            let match = haystack.range(of: query, options: .caseInsensitive, range: searchRange)
            guard match.location != NSNotFound else { break }

            // 行号：从上次数到的位置接着数换行
            while newlineCountedUpTo < match.location {
                if haystack.character(at: newlineCountedUpTo) == 0x0A { lineNumber += 1 }
                newlineCountedUpTo += 1
            }

            // 命中行全文（去掉行尾换行），面板显示上下文用
            let lineRange = haystack.lineRange(for: NSRange(location: match.location, length: 0))
            var lineText = haystack.substring(with: lineRange)
            while lineText.hasSuffix("\n") || lineText.hasSuffix("\r") {
                lineText.removeLast()
            }
            let matchInLine = NSRange(
                location: match.location - lineRange.location,
                length: match.length
            )

            found += 1
            pending.append(Hit(
                scopeIndex: scopeIndex, fileURL: fileURL, relativePath: relativePath,
                kind: .content, lineNumber: lineNumber, lineText: lineText,
                matchRangeInLine: matchInLine, occurrence: found
            ))

            let next = match.location + max(match.length, 1)
            guard next < haystack.length else { break }
            searchRange = NSRange(location: next, length: haystack.length - next)
        }
        return found
    }

    // MARK: - 展示用上下文

    /// 把原始命中行变成列表里能读的一行上下文。
    ///
    /// 原始行常常很长、带行首缩进和成串空白（表格、对齐的 Markdown），整行铺进
    /// 结果列表就是一堵字墙。处理：折叠连续空白为一个空格、去掉首尾空白；
    /// 仍太长就以命中为中心开窗，两端补省略号。
    ///
    /// 返回清理后的文本与命中词在其中的新位置（高亮用）。位置靠逐字符的
    /// 下标映射搬过去，不能重新搜 —— 一行里可能有多个相同命中（"second NEEDLE
    /// and needle again"），重搜会把所有行都高亮成第一处。
    static func displayContext(
        line: String,
        match: NSRange?,
        maxLength: Int = 120
    ) -> (text: String, matchRange: NSRange?) {
        let ns = line as NSString

        // map[i] = 原始下标 i 在清理后文本里的位置（UTF-16）
        var map = [Int](repeating: 0, count: ns.length + 1)
        var cleaned = ""
        var outIndex = 0
        var pendingSpace = false
        cleaned.reserveCapacity(ns.length)
        for i in 0..<ns.length {
            let ch = ns.character(at: i)
            if ch == 0x20 || ch == 0x09 || ch == 0x0A || ch == 0x0D {
                // 行首空白直接丢；行中的串成一串，最后只补一个
                pendingSpace = pendingSpace || outIndex > 0
                map[i] = outIndex
                continue
            }
            if pendingSpace {
                cleaned.append(" ")
                outIndex += 1
                pendingSpace = false
            }
            map[i] = outIndex
            cleaned.append(Character(UnicodeScalar(ch) ?? UnicodeScalar(0xFFFD)!))
            outIndex += 1
        }
        map[ns.length] = outIndex

        var text = cleaned
        guard let match, match.location != NSNotFound,
              match.location + match.length <= ns.length else {
            return (text, nil)
        }

        var location = map[match.location]
        let length = max(map[match.location + match.length] - location, 1)

        // 以命中为中心开窗（全程 UTF-16 下标，与 NSRange 一致）
        let cns = text as NSString
        if cns.length > maxLength {
            var start = max(0, location - maxLength / 2)
            let end = min(cns.length, start + maxLength)
            start = max(0, end - maxLength)
            text = cns.substring(with: NSRange(location: start, length: end - start))
            location -= start
            if start > 0 {
                text = "…" + text
                location += 1
            }
            if end < cns.length { text += "…" }
        }

        return (text, NSRange(location: location, length: length))
    }
}
