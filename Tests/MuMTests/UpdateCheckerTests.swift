import XCTest
@testable import MuM

/// 版本号比较测试。它决定「用户会不会收到更新提醒」——
/// 比错方向（新版说旧）= 永远没人知道有更新；比反方向 = 每次启动都误报。
final class UpdateCheckerTests: XCTestCase {

    func testNewerPatchMinorMajor() {
        XCTAssertTrue(UpdateChecker.isNewer("0.7.1", than: "0.7.0"))
        XCTAssertTrue(UpdateChecker.isNewer("0.8.0", than: "0.7.9"))
        XCTAssertTrue(UpdateChecker.isNewer("1.0.0", than: "0.99.99"))
    }

    func testSameIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("0.7.0", than: "0.7.0"))
        XCTAssertFalse(UpdateChecker.isNewer("0.7.0", than: "0.7"))
    }

    func testOlderIsNotNewer() {
        XCTAssertFalse(UpdateChecker.isNewer("0.7.0", than: "0.7.1"))
        XCTAssertFalse(UpdateChecker.isNewer("0.6.9", than: "0.7.0"))
    }

    func testNumericNotLexical() {
        // 字符串字典序下 "0.10.0" < "0.9.0" —— 版本必须按数值比
        XCTAssertTrue(UpdateChecker.isNewer("0.10.0", than: "0.9.9"))
        XCTAssertFalse(UpdateChecker.isNewer("0.9.9", than: "0.10.0"))
    }
}
