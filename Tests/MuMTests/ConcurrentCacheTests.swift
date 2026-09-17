import XCTest
@testable import MuM

/// ConcurrentCache：基本语义 + 并发读写冒烟。
final class ConcurrentCacheTests: XCTestCase {

    func testMissReturnsNil() {
        let cache = ConcurrentCache<String>()
        XCTAssertNil(cache["absent"])
    }

    func testSetGetOverwriteRemoveAll() {
        let cache = ConcurrentCache<Int>()
        cache["a"] = 1
        XCTAssertEqual(cache["a"], 1)

        cache["a"] = 2
        XCTAssertEqual(cache["a"], 2)

        cache["b"] = 3
        cache.removeAll()
        XCTAssertNil(cache["a"])
        XCTAssertNil(cache["b"])
    }

    func testConcurrentReadWriteSmoke() {
        let cache = ConcurrentCache<Int>()
        let threads = 8
        let perThread = 200
        let group = DispatchGroup()

        for t in 0..<threads {
            group.enter()
            DispatchQueue.global().async {
                defer { group.leave() }
                for i in 0..<perThread {
                    cache["t\(t)-\(i)"] = i
                    _ = cache["t\(t)-\(i)"] // 写完立刻读，与其它线程竞争同一把锁
                }
            }
        }
        XCTAssertEqual(group.wait(timeout: .now() + 10), .success)

        for t in 0..<threads {
            for i in 0..<perThread {
                XCTAssertEqual(cache["t\(t)-\(i)"], i, "并发写入后 key t\(t)-\(i) 丢失或不一致")
            }
        }
    }
}
