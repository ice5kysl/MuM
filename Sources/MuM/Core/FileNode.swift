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

    // MARK: - 图标
    // MARK: - 图标

    private static let iconCache = ConcurrentCache<NSImage>()

    /// 文件树图标。优先用系统为真实文件类型提供的图标（Finder 同款），
    /// 保证 Markdown / Swift / 图片各有辨识度，且加载结果按扩展名缓存。
    func icon() -> NSImage? {
        let key: String
        switch kind {
        case .folder: key = "dir"
        case .markdown, .code, .plainText, .richText, .image, .pdf, .unsupported:
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
}

extension URL {
    /// 解符号链接后的真实路径（realpath(3)；解不开退回原路径）。
    ///
    /// 凡是和 FileManager 扫描结果比路径的地方都必须用这个：这代 macOS 上
    /// `resolvingSymlinksInPath` 不解 /var → /private/var（实测），而
    /// contentsOfDirectory 返回的子路径是解过链接的 —— 两边不比同一个形式，
    /// 链接目录下的文件就会"在树里但找不到"（新建文件的断言抓住了这个）
    var realPath: String {
        guard let resolved = realpath(path, nil) else { return path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
