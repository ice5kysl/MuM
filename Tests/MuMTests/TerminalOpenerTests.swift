import XCTest
@testable import MuM

/// 终端探测：优先级（Ghostty > iTerm > 系统终端）与「永远在」的兜底。
/// 注入 exists 谓词，断言不依赖测试机真装了哪个终端。
final class TerminalOpenerTests: XCTestCase {

    func testGhosttyWinsWhenAllInstalled() {
        let terminal = TerminalOpener.detected { _ in true }
        XCTAssertEqual(terminal.bundleID, "com.mitchellh.ghostty")
        XCTAssertEqual(terminal.displayName, "Ghostty")
    }

    func testITermWhenNoGhostty() {
        let terminal = TerminalOpener.detected { $0 == "com.googlecode.iterm2" }
        XCTAssertEqual(terminal.bundleID, "com.googlecode.iterm2")
    }

    func testSystemTerminalAlwaysFallsBack() {
        // 什么第三方终端都没装 → 系统终端兜底（Terminal.app 永远在，探测不会落空）
        let terminal = TerminalOpener.detected { _ in false }
        XCTAssertEqual(terminal.bundleID, "com.apple.Terminal")
        XCTAssertEqual(terminal.displayName, "终端")
    }
}
