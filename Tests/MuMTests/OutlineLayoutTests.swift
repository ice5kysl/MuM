import XCTest
import AppKit
@testable import MuM

/// 文档大纲 popover 的行布局（ice 实测：H2/H3 行塌成只剩一个字符）。
/// 根因是 OutlineRowButton 依赖 NSButton 对 attributedTitle 的自测量 ——
/// 带自定义段落样式（缩进 + 截断）时 H2/H3 行的 intrinsic 宽度被量残。
final class OutlineLayoutTests: XCTestCase {

    private static var retainedWindow: NSWindow?

    func testRowsAreFullWidthAndReadable() {
        let items = [
            MarkdownRenderer.OutlineItem(level: 1, title: "WhyMyPhone 是什么", location: 0),
            MarkdownRenderer.OutlineItem(level: 2, title: "目录与使用百科", location: 10),
            MarkdownRenderer.OutlineItem(level: 2, title: "一段比较长的二级标题，应该被截断而不是塌掉", location: 20),
            MarkdownRenderer.OutlineItem(level: 3, title: "支持邮箱", location: 30),
        ]
        let controller = PreviewOutlineView(items: items)

        // 不关窗、不释放：测试进程里没有完整应用生命周期，提前 close 会在
        // autorelease pool 收尾时 double-free（实测 SIGSEGV）。泄漏一个窗口
        // 对一次性测试进程无害
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 300, height: 200),
            styleMask: [.titled], backing: .buffered, defer: false)
        Self.retainedWindow = window
        let host = window.contentView!
        let view = controller.view
        view.frame = host.bounds
        host.addSubview(view)
        window.layoutIfNeeded()
        view.layoutSubtreeIfNeeded()

        let buttons = allSubviews(of: view).compactMap { $0 as? NSButton }
        XCTAssertEqual(buttons.count, items.count, "每条大纲一行")
        for (index, button) in buttons.enumerated() {
            XCTAssertGreaterThanOrEqual(
                button.frame.width, 280,
                "第 \(index) 行（L\(items[index].level)）宽度塌了：\(button.frame.width)")
            XCTAssertGreaterThanOrEqual(
                button.frame.height, 20,
                "第 \(index) 行（L\(items[index].level)）高度塌了：\(button.frame.height)")
        }
    }

    private func allSubviews(of view: NSView) -> [NSView] {
        [view] + view.subviews.flatMap { allSubviews(of: $0) }
    }
}
