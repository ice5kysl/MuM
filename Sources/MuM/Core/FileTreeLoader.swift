import Foundation

/// 目录扫描。
///
/// 两件事：把纯粹的噪音目录挡在树外，以及保证排序稳定（目录在前、名称自然序），
/// 让文件树看起来始终是「整理过」的，而不是 `ls` 的原始输出。
enum FileTreeLoader {

    /// 这些目录名不出现在文件树里。判断标准是「几乎不可能放用户想读的 Markdown」。
    static let ignoredDirectoryNames: Set<String> = [
        ".git", ".svn", ".hg", ".build", ".swiftpm",
        "node_modules", "bower_components", "Pods", "Carthage", "DerivedData",
        "__pycache__", ".venv", "venv", ".mypy_cache", ".pytest_cache", ".ruff_cache",
        ".next", ".nuxt", ".cache", ".parcel-cache", ".turbo", ".gradle",
        ".Trash", ".Spotlight-V100", ".fseventsd", ".DocumentRevisions-V100",
    ]

    /// 是否显示 `.` 开头的隐藏文件。由系统设置驱动。
    static var showsHiddenFiles = false

    /// 是否应当从文件树中隐藏
    static func shouldIgnore(url: URL) -> Bool {
        let name = url.lastPathComponent
        guard !name.isEmpty else { return true }
        if name == ".DS_Store" { return true }
        // 忽略列表是"永远不想要"（.git、node_modules、DerivedData…），
        // 和"隐藏文件"是两回事，不受开关影响。
        if ignoredDirectoryNames.contains(name) { return true }
        if !showsHiddenFiles, name.hasPrefix(".") { return true }
        return false
    }

    /// 扫描一个目录的直接子项
    static func children(of directory: URL, parent: FileNode) -> [FileNode] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .nameKey]
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        var nodes: [FileNode] = []
        nodes.reserveCapacity(entries.count)

        for entry in entries {
            if shouldIgnore(url: entry) { continue }
            nodes.append(FileNode(url: entry, parent: parent))
        }

        nodes.sort { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }

        return nodes
    }
}
