import XCTest
import AppKit
@testable import MuM

/// 预览链接的内部打开 + 阅读历史（⌘[ / ⌘]）。
/// 回归锚点：textView.delegate 曾经漏接线 —— clickedOnLink 写了却从没被调用，
/// 链接点击全走了系统默认（ice 实测：表格里的 .md 链接点了没反应）。
final class NavigationHistoryTests: XCTestCase {

    /// 见 OutlineLayoutTests：测试进程里没有完整应用生命周期，
    /// 提前释放窗口/控制器会在 autorelease pool 收尾时 SIGSEGV
    private static var retained: [AnyObject] = []

    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("mum-nav-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - 链接

    func testPreviewTextViewDelegateIsWired() {
        let controller = PreviewViewController()
        _ = controller.view
        Self.retained.append(controller)
        XCTAssertNotNil(controller.previewTextView.delegate,
                        "delegate 漏接线的话 clickedOnLink 永远不会被调用")
    }

    func testFileLinkGoesToInternalHandler() {
        let controller = PreviewViewController()
        _ = controller.view
        Self.retained.append(controller)

        var received: URL?
        controller.onOpenInternalLink = { url in
            received = url
            return true
        }
        let fileURL = URL(fileURLWithPath: "/tmp/some-doc.md")
        let handled = controller.textView(
            controller.previewTextView, clickedOnLink: fileURL, at: 0)
        XCTAssertTrue(handled)
        XCTAssertEqual(received, fileURL)
    }

    // MARK: - 前进 / 后退

    func testBackAndForward() throws {
        let a = try write("# A\n", "a.md")
        let b = try write("# B\n", "b.md")
        let c = try write("# C\n", "c.md")

        let controller = MainWindowController()
        Self.retained.append(controller)

        XCTAssertFalse(controller.canGoBack)

        controller.open(url: a)
        controller.open(url: b)
        XCTAssertEqual(controller.window?.title, "b.md")
        XCTAssertTrue(controller.canGoBack, "从 a 走到 b，a 应该进后退栈")

        controller.goBack()
        XCTAssertEqual(controller.window?.title, "a.md")
        XCTAssertTrue(controller.canGoForward, "回到 a 之后，b 应该进前进栈")

        controller.goForward()
        XCTAssertEqual(controller.window?.title, "b.md")

        // 从 b 走到 c：前进栈清空（浏览器语义）
        controller.open(url: c)
        XCTAssertFalse(controller.canGoForward)

        controller.goBack()
        controller.goBack()
        XCTAssertEqual(controller.window?.title, "a.md")
        XCTAssertFalse(controller.canGoBack, "栈底了")
    }

    private func write(_ text: String, _ name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try text.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
