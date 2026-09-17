import AppKit
import UniformTypeIdentifiers

/// 文件树节点。
///
/// 子节点按需加载：只有展开某个目录时才扫描它的磁盘内容。这样即便项目根目录下有
/// 几万个文件，打开项目也是瞬时的，代价只发生在大到用户真正点开的那一层。
final class FileNode {
    let url: URL
    let isDirectory: Bool
    let kind: FileKind

    weak var parent: FileNode?
    /// nil 表示「尚未从磁盘读取过」；非 nil（哪怕是空数组）表示已加载
    private(set) var children: [FileNode]?

    var isLoaded: Bool { children != nil }

    var name: String { url.lastPathComponent }

    init(url: URL, parent: FileNode? = nil) {
        self.url = url
        self.parent = parent

        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        self.isDirectory = isDir
        self.kind = FileKind(url: url, isDirectory: isDir)
    }

    /// 从磁盘加载直接子节点（目录优先、再按名称自然排序）
    @discardableResult
    func loadChildren() -> [FileNode] {
        if let children { return children }
        let loaded = isDirectory ? FileTreeLoader.children(of: url, parent: self) : []
        children = loaded
        return loaded
    }

    /// 丢弃缓存，下次访问重新扫描（用于文件系统变动后的刷新）
    func invalidate() {
        children = nil
    }

    /// 从根到自身的路径，用于在树里定位
    var indexPath: [Int] {
        var path: [Int] = []
        var node: FileNode? = self
        while let current = node, let parent = current.parent {
            guard let siblings = parent.children,
                  let index = siblings.firstIndex(where: { $0 === current }) else { break }
            path.insert(index, at: 0)
            node = parent
        }
        return path
    }

    // MARK: - 图标

    private static let iconCache = ConcurrentCache<NSImage>()

    /// 文件树图标。优先用系统为真实文件类型提供的图标（Finder 同款），
    /// 保证 Markdown / Swift / 图片各有辨识度，且加载结果按扩展名缓存。
    func icon() -> NSImage? {
        let key: String
        switch kind {
        case .folder: key = "dir"
        case .markdown, .code, .plainText, .image, .pdf, .unsupported:
            key = url.pathExtension.lowercased()
        }

        if let cached = FileNode.iconCache[key] { return cached }

        let image: NSImage?
        if isDirectory {
            image = NSWorkspace.shared.icon(for: .folder)
        } else if key.isEmpty {
            image = NSWorkspace.shared.icon(forFile: url.path)
        } else {
            image = NSWorkspace.shared.icon(for: UTType(filenameExtension: key) ?? .data)
        }

        let sized = image?.copy() as? NSImage
        sized?.size = NSSize(width: 16, height: 16)
        if let sized { FileNode.iconCache[key] = sized }
        return sized
    }

    static func clearIconCache() {
        iconCache.removeAll()
    }
}
