import AppKit

/// 一个打开的项目（一个文件夹）。
///
/// MuM 的「项目」概念刻意做到最轻：就是一个文件夹路径 + 一棵按需加载的文件树，
/// 没有 workspace 配置文件、没有索引、没有语言服务器。切换项目因此是零成本的。
final class Workspace: Identifiable {
    let id = UUID()
    let rootURL: URL
    let root: FileNode

    init(rootURL: URL) {
        self.rootURL = rootURL.standardizedFileURL
        self.root = FileNode(url: self.rootURL)
    }

    var name: String { rootURL.lastPathComponent }

    /// 侧边栏悬浮提示用的完整路径，`~` 缩写
    var displayPath: String {
        (rootURL.path as NSString).abbreviatingWithTildeInPath
    }

    var icon: NSImage? {
        let image = NSWorkspace.shared.icon(forFile: rootURL.path)
        let copy = image.copy() as? NSImage
        copy?.size = NSSize(width: 16, height: 16)
        return copy
    }

    /// 树里所有已加载的目录节点，文件系统变动后据此逐个失效并重载
    func loadedDirectories() -> [FileNode] {
        var result: [FileNode] = []
        var stack: [FileNode] = [root]
        while let node = stack.popLast() {
            guard node.isDirectory, node.isLoaded else { continue }
            result.append(node)
            if let children = node.children {
                stack.append(contentsOf: children.filter { $0.isDirectory })
            }
        }
        return result
    }
}
