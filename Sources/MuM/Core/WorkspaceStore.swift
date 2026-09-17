import AppKit

/// 多项目工作区管理：打开列表、激活项、持久化。
///
/// Cmd+1…9 直接索引 `workspaces`，所以「切项目」是一次数组下标访问加一次界面刷新，
/// 没有任何磁盘往返 —— 这是 MuM 快速切项目的核心。
///
/// `@unchecked Sendable`：这个类型只在主线程被访问（全部调用点都在 UI 路径上），
/// 标它是为了让 `shared` 这个全局常量通过并发检查，而不是引入 actor 隔离。
final class WorkspaceStore: @unchecked Sendable {

    static let shared = WorkspaceStore()

    private let listKey = "MuM.workspacePaths"
    private let activeKey = "MuM.activeWorkspaceIndex"

    private(set) var workspaces: [Workspace] = []
    private(set) var activeIndex: Int = 0

    var active: Workspace? {
        guard !workspaces.isEmpty else { return nil }
        let index = workspaces.indices.contains(activeIndex) ? activeIndex : 0
        return workspaces[index]
    }

    var count: Int { workspaces.count }

    private init() {
        restore()
    }

    // MARK: - 打开 / 关闭

    /// 打开一个文件夹作为项目。已打开则直接切过去，不重复添加。
    @discardableResult
    func open(url: URL) -> Workspace? {
        let standardized = url.standardizedFileURL

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: standardized.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            return nil
        }

        if let existing = workspaces.firstIndex(where: { $0.rootURL == standardized }) {
            activate(index: existing)
            return workspaces[existing]
        }

        let workspace = Workspace(rootURL: standardized)
        workspaces.append(workspace)
        activeIndex = workspaces.count - 1
        persist()

        NotificationCenter.default.post(name: .mumWorkspaceListChanged, object: self)
        NotificationCenter.default.post(name: .mumActiveWorkspaceChanged, object: self)
        return workspace
    }

    /// 弹出系统选择框让用户挑文件夹
    func promptForFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = true
        panel.prompt = "打开"
        panel.message = "选择一个文件夹作为 MuM 项目"

        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            open(url: url)
        }
    }

    func close(index: Int) {
        guard workspaces.indices.contains(index) else { return }
        workspaces.remove(at: index)

        if workspaces.isEmpty {
            activeIndex = 0
        } else if index < activeIndex {
            activeIndex -= 1
        } else if index == activeIndex {
            activeIndex = min(activeIndex, workspaces.count - 1)
        }

        persist()
        NotificationCenter.default.post(name: .mumWorkspaceListChanged, object: self)
        NotificationCenter.default.post(name: .mumActiveWorkspaceChanged, object: self)
    }

    func closeActive() {
        guard !workspaces.isEmpty else { return }
        close(index: activeIndex)
    }

    // MARK: - 切换

    func activate(index: Int) {
        guard workspaces.indices.contains(index), index != activeIndex else { return }
        activeIndex = index
        persist()
        NotificationCenter.default.post(name: .mumActiveWorkspaceChanged, object: self)
    }

    /// Cmd+1…9：索引 0…8
    func activateShortcut(_ shortcutIndex: Int) {
        activate(index: shortcutIndex)
    }

    func activateNext() {
        guard workspaces.count > 1 else { return }
        activate(index: (activeIndex + 1) % workspaces.count)
    }

    func activatePrevious() {
        guard workspaces.count > 1 else { return }
        activate(index: (activeIndex - 1 + workspaces.count) % workspaces.count)
    }

    /// 把当前项目在列表里左右移动，用来固化 Cmd+数字 的肌肉记忆
    func moveActive(by delta: Int) {
        let target = activeIndex + delta
        guard workspaces.indices.contains(target) else { return }
        let workspace = workspaces.remove(at: activeIndex)
        workspaces.insert(workspace, at: target)
        activeIndex = target
        persist()
        NotificationCenter.default.post(name: .mumWorkspaceListChanged, object: self)
        NotificationCenter.default.post(name: .mumActiveWorkspaceChanged, object: self)
    }

    // MARK: - 上次打开的文件
    //
    // 切回一个项目时应该回到上次在读的那一篇，而不是空白的欢迎界面。
    // 这是「便捷切换项目」体验里最容易被忽略、但用起来感知最强的一环。

    private let lastFileKey = "MuM.lastOpenedFiles"

    func lastOpenedFile(for workspace: Workspace) -> URL? {
        guard let map = UserDefaults.standard.dictionary(forKey: lastFileKey) as? [String: String],
              let relative = map[workspace.rootURL.path] else { return nil }
        let url = workspace.rootURL.appendingPathComponent(relative)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func rememberOpenedFile(_ url: URL, in workspace: Workspace) {
        let root = workspace.rootURL.path
        guard url.path.hasPrefix(root + "/") else { return }

        var map = (UserDefaults.standard.dictionary(forKey: lastFileKey) as? [String: String]) ?? [:]
        map[root] = String(url.path.dropFirst(root.count + 1))
        UserDefaults.standard.set(map, forKey: lastFileKey)
    }

    // MARK: - 持久化

    private func persist() {
        let paths = workspaces.map { $0.rootURL.path }
        UserDefaults.standard.set(paths, forKey: listKey)
        UserDefaults.standard.set(activeIndex, forKey: activeKey)
    }

    private func restore() {
        let paths = UserDefaults.standard.stringArray(forKey: listKey) ?? []
        for path in paths {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
                  isDirectory.boolValue else { continue }
            workspaces.append(Workspace(rootURL: URL(fileURLWithPath: path)))
        }

        let saved = UserDefaults.standard.integer(forKey: activeKey)
        activeIndex = workspaces.indices.contains(saved) ? saved : 0
    }
}
