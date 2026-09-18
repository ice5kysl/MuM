import Foundation

/// 基于 FSEvents 的目录监听。
///
/// 用 FSEvents 而不是轮询或 kqueue：FSEvents 由内核在目录树上做聚合，递归监听一个
/// 大项目也只有一次注册，且事件按时间窗口合并 —— 对一个「文件变了就刷新树和预览」
/// 的场景正好。变化先在这里去抖，再回到主线程通知界面。
///
/// 线程模型：start/stop 由主线程调用，FSEvents 回调投递到串行 queue。
/// **一切可变状态（stream / pending / boxRef）只在 queue 上碰** —— stop 用
/// `queue.sync` 挤进同一个队，等于把在途回调全部排空再动手，回调永远碰不到
/// 已释放的资源（审计 C-1/C-2）。回调与工作项都不强持 self，deinit 不可能
/// 发生在 queue 上，这里的 sync 不会自死锁。
final class FileWatcher {

    /// 回调载体。stream 的 context 必须带一个稳定指针，直接挂 unretained self
    /// 就是 use-after-free：deinit 的 stop() 与在途回调之间没有任何同步。
    /// 改为 stream 生命周期内强持这个盒子（+1 手工平衡），盒子弱指回 self ——
    /// 回调拿到的一定是活盒子，self 没了只是 nil。
    private final class CallbackBox {
        weak var owner: FileWatcher?
    }

    private let path: String
    private let latency: CFTimeInterval
    private let handler: () -> Void

    private var stream: FSEventStreamRef?
    private var pending: DispatchWorkItem?
    /// stream context 里那枚 +1 的句柄，stop 时在 queue 上 release 掉
    private var boxRef: Unmanaged<CallbackBox>?
    private let queue = DispatchQueue(label: "ai.mum.filewatcher", qos: .utility)

    init(path: String, latency: CFTimeInterval = 0.25, handler: @escaping () -> Void) {
        self.path = path
        self.latency = latency
        self.handler = handler
    }

    deinit {
        stop()
    }

    /// 主线程调用。只碰 stream 的创建与注册，可变状态仍全部落在 queue 之前
    /// （调用方保证 start 不会与 stop 并发 —— MainWindowController 全部在主线程）。
    func start() {
        guard stream == nil else { return }

        let box = CallbackBox()
        box.owner = self
        let boxRef = Unmanaged.passRetained(box) // +1，stream 存续期间归它
        var context = FSEventStreamContext(
            version: 0,
            info: boxRef.toOpaque(),
            retain: nil,
            release: nil,
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, info, _, _, _, _ in
            guard let info else { return }
            // 盒子在 stop() 释放前一直被 +1 托着，而 stop 要在 queue 上排空
            // 所有在途回调后才 release —— 这里的解引用必然安全
            let box = Unmanaged<CallbackBox>.fromOpaque(info).takeUnretainedValue()
            box.owner?.scheduleFire()
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
            boxRef.release()
            return
        }

        self.stream = stream
        self.boxRef = boxRef
        FSEventStreamSetDispatchQueue(stream, queue)
        FSEventStreamStart(stream)
    }

    /// 主线程调用。可重入：未启动或已停止时是 no-op。
    func stop() {
        queue.sync {
            // pending 只在这队上读写：这里 cancel 之后，scheduleFire 不可能再
            // 从别的线程塞一个新的回来
            pending?.cancel()
            pending = nil

            guard let stream else { return }
            self.stream = nil
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)

            // 在途回调已被本 sync 排空，stream 也已停 —— 不会再有回调碰盒子
            boxRef?.release()
            boxRef = nil
        }
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
