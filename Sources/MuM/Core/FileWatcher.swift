import Foundation

/// 基于 FSEvents 的目录监听。
///
/// 用 FSEvents 而不是轮询或 kqueue：FSEvents 由内核在目录树上做聚合，递归监听一个
/// 大项目也只有一次注册，且事件按时间窗口合并 —— 对一个「文件变了就刷新树和预览」
/// 的场景正好。变化先在这里去抖，再回到主线程通知界面。
final class FileWatcher {

    private let path: String
    private let latency: CFTimeInterval
    private let handler: () -> Void

    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?
    private let queue = DispatchQueue(label: "ai.mum.filewatcher", qos: .utility)

    init(path: String, latency: CFTimeInterval = 0.25, handler: @escaping () -> Void) {
        self.path = path
        self.latency = latency
        self.handler = handler
    }

    deinit {
        stop()
    }

    var isRunning: Bool { stream != nil }

    func start() {
        guard stream == nil else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passUnretained(self).toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            Unmanaged<FileWatcher>.fromOpaque(info).takeUnretainedValue().scheduleFire()
        }

        let flags = UInt32(
            kFSEventStreamCreateFlagFileEvents |
            kFSEventStreamCreateFlagNoDefer |
            kFSEventStreamCreateFlagWatchRoot
        )

        guard let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            [path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            latency,
            flags
        ) else {
            return
        }

        self.stream = stream
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    func stop() {
        pending?.cancel()
        pending = nil

        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }

    private func scheduleFire() {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            DispatchQueue.main.async { self.handler() }
        }
        pending = work
        queue.asyncAfter(deadline: .now() + latency, execute: work)
    }
}
