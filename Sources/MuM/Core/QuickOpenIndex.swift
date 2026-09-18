import Foundation

/// ⌘P 快速打开的文件索引与模糊匹配。
///
/// 索引是工作区根目录的扁平文件清单（过滤规则与文件树一致），后台构建、按项目缓存；
/// 匹配是纯字符串运算 —— 1 万文件单次过滤是毫秒级，瓶颈在首次扫描的 IO，
/// 所以扫描永远在后台，面板先显示缓存、扫完再换。
final class QuickOpenIndex {

    struct Entry {
        let url: URL
        /// 相对项目根的路径，展示用
        let relativePath: String
        let name: String
    }

    private(set) var entries: [Entry] = []
    /// 索引对应的项目根；换了项目就要重建
    private(set) var rootPath: String?

    init() {}

    /// 测试与合成基准用：直接给一份现成清单，不走磁盘扫描
    init(entries: [Entry]) {
        self.entries = entries
    }

    /// 上限防爆：索引是为了"按名字找文件"，超过这个量级的目录树，
    /// 快速打开也不是正确的工具
    private static let maxEntries = 50_000

    // MARK: - 扫描（后台线程）

    /// 在后台重建索引，完成后在主线程回调条数。
    /// FileManager 枚举是纯 IO，不进主线程 —— 1 万文件首次扫描大约百毫秒。
    func rebuild(root: URL, completion: @escaping (Int) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let entries = Self.scan(root: root)
            DispatchQueue.main.async {
                guard let self else { return }
                self.entries = entries
                self.rootPath = root.path
                completion(entries.count)
            }
        }
    }

    private static func scan(root: URL) -> [Entry] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return [] }

        var entries: [Entry] = []
        entries.reserveCapacity(1024)
        let rootPath = root.path + "/"

        for case let url as URL in enumerator {
            if FileTreeLoader.shouldIgnore(url: url) {
                // 是目录就别再往里走了
                if (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                    enumerator.skipDescendants()
                }
                continue
            }
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == false else { continue }
            let path = url.path
            entries.append(Entry(
                url: url,
                relativePath: path.hasPrefix(rootPath) ? String(path.dropFirst(rootPath.count)) : url.lastPathComponent,
                name: url.lastPathComponent
            ))
            if entries.count >= maxEntries { break }
        }
        return entries
    }

    // MARK: - 模糊匹配

    /// 子序列模糊匹配，按相关度排序，至多返回 limit 条。
    /// 匹配对象是文件名；同分时路径短的在前面（浅的文件更常是要找的）。
    func matching(_ query: String, limit: Int = 50) -> [Entry] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Array(entries.prefix(limit)) }

        var scored: [(entry: Entry, score: Int)] = []
        scored.reserveCapacity(256)
        for entry in entries {
            if let score = Self.fuzzyScore(query: trimmed, name: entry.name) {
                scored.append((entry, score))
            }
        }
        scored.sort { lhs, rhs in
            if lhs.score != rhs.score { return lhs.score > rhs.score }
            if lhs.entry.relativePath.count != rhs.entry.relativePath.count {
                return lhs.entry.relativePath.count < rhs.entry.relativePath.count
            }
            return lhs.entry.name.localizedStandardCompare(rhs.entry.name) == .orderedAscending
        }
        return Array(scored.prefix(limit).map(\.entry))
    }

    /// 打分：query 的每个字符按序出现在 name 里才命中（大小写不敏感）。
    /// 连续命中加分、词边界（`/ - _ .` 之后、大小写驼峰切换处）命中加分，
    /// 跳过的字符扣分 —— 分数只用来排序，没有绝对意义。
    static func fuzzyScore(query: String, name: String) -> Int? {
        let queryChars = Array(query.lowercased())
        let nameChars = Array(name)
        let lowered = name.lowercased()
        let loweredChars = Array(lowered)
        guard !queryChars.isEmpty else { return 0 }

        var score = 0
        var qi = 0
        var lastMatch = -2
        for (ni, char) in loweredChars.enumerated() where qi < queryChars.count {
            guard char == queryChars[qi] else { continue }
            score += 1
            if ni == lastMatch + 1 { score += 8 } // 连续
            if ni == 0 { score += 10 }            // 开头
            else {
                let prev = nameChars[nameChars.index(nameChars.startIndex, offsetBy: ni - 1)]
                if "/ -_.".contains(prev) { score += 10 } // 词边界
                else if prev.isLowercase, nameChars[nameChars.index(nameChars.startIndex, offsetBy: ni)].isUppercase {
                    score += 10                              // 驼峰边界
                }
            }
            score -= (ni - lastMatch - 1) // 间隙
            lastMatch = ni
            qi += 1
        }
        return qi == queryChars.count ? score : nil
    }
}
