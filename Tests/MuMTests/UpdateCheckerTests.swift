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

    // MARK: - 资产挑选（一键下载的直链来源）

    private func releaseJSON(_ assets: [[String: Any]]) -> [String: Any] {
        ["tag_name": "v0.7.3", "html_url": "https://example.com/r", "assets": assets]
    }

    func testPickAssetPrefersDMG() {
        let json = releaseJSON([
            ["name": "MuM-0.7.3.zip", "browser_download_url": "https://x/m.zip", "size": 100],
            ["name": "MuM-0.7.3.dmg", "browser_download_url": "https://x/m.dmg", "size": 200],
        ])
        let picked = UpdateChecker.pickAsset(from: json)
        XCTAssertEqual(picked?.url.absoluteString, "https://x/m.dmg", "DMG 优先于 ZIP")
        XCTAssertEqual(picked?.size, 200)
    }

    func testPickAssetFallsBackToZIP() {
        let json = releaseJSON([
            ["name": "MuM-0.7.3.zip", "browser_download_url": "https://x/m.zip"],
        ])
        XCTAssertEqual(UpdateChecker.pickAsset(from: json)?.url.absoluteString, "https://x/m.zip")
    }

    func testPickAssetNilWhenNoUsableAsset() {
        XCTAssertNil(UpdateChecker.pickAsset(from: releaseJSON([])), "空资产列表")
        XCTAssertNil(UpdateChecker.pickAsset(from: releaseJSON([
            ["name": "源码.tar.gz", "browser_download_url": "https://x/s.tar.gz"],
        ])), "非 DMG/ZIP 不选")
        XCTAssertNil(UpdateChecker.pickAsset(from: ["tag_name": "v1.0.0"]), "没有 assets 字段")
    }
}
