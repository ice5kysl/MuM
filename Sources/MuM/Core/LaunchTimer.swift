import Foundation

/// 启动耗时打点。
///
/// 只在 `MUM_LAUNCH_TIMING=1` 时输出 —— 平时连一次 Date() 都不多做。
/// 存在的理由：说"MuM 很快"之前，得先知道时间花在哪。渲染只要 0.03s，
/// 但进程到窗口要 1.2s，差的这 1.2s 必须先被看见，才谈得上优化。
enum LaunchTimer {

    private static let enabled = ProcessInfo.processInfo.environment["MUM_LAUNCH_TIMING"] != nil

    /// t0。进程一进来就赋值，之后所有打点都是相对它的偏移。
    static var origin = Date()

    static func mark(_ label: String) {
        guard enabled else { return }
        let ms = Date().timeIntervalSince(origin) * 1000
        let line = String(format: "[启动] %8.1f ms  %@\n", ms, label)
        FileHandle.standardError.write(line.data(using: .utf8)!)
    }
}
