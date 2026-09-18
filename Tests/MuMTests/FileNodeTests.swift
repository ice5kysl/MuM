import XCTest
@testable import MuM

/// FileNode：按需加载、失效重扫，以及 FileTreeLoader 的过滤与排序。
final class FileNodeTests: XCTestCase {

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mum-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        try "hello".write(to: root.appendingPathComponent("a.md"), atomically: true, encoding: .utf8)
        try Data([0x00, 0x01]).write(to: root.appendingPathComponent("z.bin"))
        let sub = root.appendingPathComponent("zdir")
        try FileManager.default.createDirectory(at: sub, withIntermediateDirectories: true)
        try "sub doc".write(to: sub.appendingPathComponent("c.md"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testLazyLoadAndDirectoryFirstOrdering() {
        let node = FileNode(url: root)
        XCTAssertTrue(node.isDirectory)
        XCTAssertFalse(node.isLoaded)

        let children = node.loadChildren()
        XCTAssertTrue(node.isLoaded)
        // 目录优先，再按名称自然排序：zdir（目录）排在 a.md / z.bin 前面
        XCTAssertEqual(children.map(\.name), ["zdir", "a.md", "z.bin"])
    }

    func testFileNodeLoadsNoChildren() {
        let file = FileNode(url: root.appendingPathComponent("a.md"))
        XCTAssertFalse(file.isDirectory)
        XCTAssertTrue(file.loadChildren().isEmpty)
    }

    func testInvalidateRescansDisk() throws {
        let node = FileNode(url: root)
        _ = node.loadChildren()

        try "new".write(to: root.appendingPathComponent("new.md"), atomically: true, encoding: .utf8)
        // 已加载的缓存不会自动感知磁盘变动
        XCTAssertEqual(node.loadChildren().map(\.name), ["zdir", "a.md", "z.bin"])

        node.invalidate()
        XCTAssertFalse(node.isLoaded)
        XCTAssertTrue(node.loadChildren().map(\.name).contains("new.md"), "失效后重扫应看到新增文件")
    }

    func testKindsOfFixtureChildren() {
        let node = FileNode(url: root)
        let byName = Dictionary(uniqueKeysWithValues: node.loadChildren().map { ($0.name, $0.kind) })
        XCTAssertEqual(byName["a.md"], .markdown)
        XCTAssertEqual(byName["z.bin"], .unsupported)
        XCTAssertEqual(byName["zdir"], .folder)
    }

    // MARK: - FileTreeLoader 过滤

    func testNoiseEntriesAreIgnored() throws {
        for name in [".DS_Store", ".git", "node_modules"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try "n".write(to: root.appendingPathComponent(".hidden.md"), atomically: true, encoding: .utf8)

        let node = FileNode(url: root)
        let names = node.loadChildren().map(\.name)
        XCTAssertEqual(names, ["zdir", "a.md", "z.bin"], "噪音目录、.DS_Store 和隐藏文件都不应出现")
    }
}
