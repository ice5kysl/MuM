import Foundation

/// 一个加锁的字典缓存。
///
/// 之所以不直接写 `static var cache: [String: T] = [:]`：非隔离的全局可变状态在
/// Swift 6 严格并发下是编译错误，而这些缓存确实只是一层「算一次、存起来」的优化，
/// 不值得为它们引入 actor 隔离并波及整条调用链。加锁表达的事实更准确。
final class ConcurrentCache<Value>: @unchecked Sendable {

    private var storage: [String: Value] = [:]
    private let lock = NSLock()

    subscript(key: String) -> Value? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storage[key]
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storage[key] = newValue
        }
    }

    func removeAll() {
        lock.lock()
        defer { lock.unlock() }
        storage.removeAll()
    }
}
