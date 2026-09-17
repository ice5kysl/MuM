import XCTest
@testable import MuM

/// WorkspaceStore 的状态迁移：打开/关闭/切换/移动时 activeIndex 的演化。
/// 核心不变量：任何迁移之后 active 必须指向合法条目，或列表为空时为 nil。
final class WorkspaceStoreTests: XCTestCase {

    private var store: WorkspaceStore!
    private var dirs: [URL] = []

    override func setUpWithError() throws {
        store = WorkspaceStore.shared
        // 单例：清空遗留状态，测试之间互不串扰
        while store.count > 0 { store.close(index: 0) }

        for i in 0..<3 {
            let dir = FileManager.default.temporaryDirectory
                .appendingPathComponent("mum-ws-\(i)-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            dirs.append(dir)
        }
    }

    override func tearDownWithError() throws {
        while store.count > 0 { store.close(index: 0) }
        for d in dirs { try? FileManager.default.removeItem(at: d) }
        UserDefaults.standard.removeObject(forKey: "MuM.workspacePaths")
        UserDefaults.standard.removeObject(forKey: "MuM.activeWorkspaceIndex")
    }

    func testOpenDeduplicatesAndActivates() {
        XCTAssertNil(store.active, "空列表时 active 应为 nil")

        store.open(url: dirs[0])
        XCTAssertEqual(store.count, 1)
        XCTAssertEqual(store.active?.rootURL, dirs[0].standardizedFileURL)

        store.open(url: dirs[0]) // 重复打开同一个 → 切过去，不新增
        XCTAssertEqual(store.count, 1)
    }

    func testOpenFileURLIsRejected() throws {
        let file = dirs[0].appendingPathComponent("f.txt")
        try "x".write(to: file, atomically: true, encoding: .utf8)
        let before = store.count
        XCTAssertNil(store.open(url: file), "打开文件（非目录）应返回 nil")
        XCTAssertEqual(store.count, before)
    }

    func testActivateGuardAndWraparound() {
        for d in dirs { store.open(url: d) }
        XCTAssertEqual(store.count, 3)
        XCTAssertEqual(store.activeIndex, 2, "最新打开的自动激活")

        store.activate(index: 99) // 越界不动
        XCTAssertEqual(store.activeIndex, 2)
        store.activate(index: 2) // 相同索引不动
        XCTAssertEqual(store.activeIndex, 2)

        store.activateNext() // 2 → 0 回绕
        XCTAssertEqual(store.activeIndex, 0)
        store.activatePrevious() // 0 → 2 回绕
        XCTAssertEqual(store.activeIndex, 2)
    }

    func testCloseAdjustsActiveIndex() {
        for d in dirs { store.open(url: d) }
        store.activate(index: 1)

        store.close(index: 0) // 关掉 active 前面的 → active 前移
        XCTAssertEqual(store.count, 2)
        XCTAssertEqual(store.activeIndex, 0)
        XCTAssertEqual(store.active?.rootURL, dirs[1].standardizedFileURL)

        store.close(index: 0) // 关掉 active 本身 → 落到剩下的条目
        XCTAssertEqual(store.active?.rootURL, dirs[2].standardizedFileURL)

        store.close(index: 0) // 清空
        XCTAssertEqual(store.count, 0)
        XCTAssertNil(store.active)

        store.closeActive() // 空态关闭不崩溃
        XCTAssertEqual(store.count, 0)
    }

    func testMoveActiveBounds() {
        for d in dirs { store.open(url: d) }
        store.activate(index: 0)

        store.moveActive(by: -1) // 越界不动
        XCTAssertEqual(store.activeIndex, 0)

        store.moveActive(by: 1) // 把第一个工作区右移一位
        XCTAssertEqual(store.activeIndex, 1)
        XCTAssertEqual(store.active?.rootURL, dirs[0].standardizedFileURL, "移动的是工作区本身")
    }

    func testPersistWritesPathList() {
        store.open(url: dirs[0])
        store.open(url: dirs[1])
        let saved = UserDefaults.standard.stringArray(forKey: "MuM.workspacePaths") ?? []
        XCTAssertEqual(saved, [
            dirs[0].standardizedFileURL.path,
            dirs[1].standardizedFileURL.path,
        ])
    }
}
