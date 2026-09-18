import Foundation

extension Notification.Name {
    /// 打开的项目列表发生变化（新增 / 关闭 / 重排）
    static let mumWorkspaceListChanged = Notification.Name("MuM.workspaceListChanged")
    /// 当前激活的项目切换了
    static let mumActiveWorkspaceChanged = Notification.Name("MuM.activeWorkspaceChanged")
    /// 磁盘上的文件树发生变化，界面需要刷新
    static let mumFileTreeChanged = Notification.Name("MuM.fileTreeChanged")
    /// 请求把焦点移到文件树过滤框
    static let mumFocusFileFilter = Notification.Name("MuM.focusFileFilter")
}
