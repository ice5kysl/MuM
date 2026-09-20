import XCTest
import AppKit
@testable import MuM

/// 选中文字的右键快捷操作（拷贝 / 在文档中查找 / 在所有项目中搜索）。
final class SelectionMenuTests: XCTestCase {

    private static var retained: [AnyObject] = []

    private func makeTextView() -> PreviewTextView {
        let controller = PreviewViewController()
        _ = controller.view
        Self.retained.append(controller)
        return controller.previewTextView
    }

    func testNoSelectionOnlyHasBasicItems() {
        let menu = makeTextView().selectionMenu(selectedText: nil)
        let titles = menu.items.map(\.title)
        XCTAssertEqual(titles, ["拷贝", "全选"], "没选中就不该出现查找项")
    }

    func testSelectionAddsTwoFindActions() {
        let menu = makeTextView().selectionMenu(selectedText: "traefik")
        let titles = menu.items.map(\.title)
        XCTAssertTrue(titles.contains("在文档中查找「traefik」"))
        XCTAssertTrue(titles.contains("在所有项目中搜索「traefik」"))

        let findItem = menu.items.first { $0.title.contains("在文档中查找") }
        XCTAssertEqual(findItem?.representedObject as? String, "traefik",
                       "完整选词要带在 representedObject 里，动作回调靠它")
    }

    func testLongSelectionIsTruncatedInTitleButNotInQuery() {
        let long = "一段足够长的中文测试文本，用来验证选中菜单不会盖住内容"
        let menu = makeTextView().selectionMenu(selectedText: long)
        let findItem = menu.items.first { $0.title.contains("在文档中查找") }
        XCTAssertTrue(findItem!.title.contains("…"), "菜单标题要截断，不能撑爆菜单")
        XCTAssertEqual(findItem?.representedObject as? String, long,
                       "查询词保持完整，截断只发生在显示层")
    }

    func testSearchQueryCollapsesWhitespaceAndTrims() {
        XCTAssertEqual(
            PreviewTextView.searchQuery(from: "  多行\n选择   变一行  "),
            "多行 选择 变一行")
        XCTAssertNil(PreviewTextView.searchQuery(from: "   \n  "),
                     "纯空白选择不该产生查询")
        XCTAssertNil(PreviewTextView.searchQuery(from: nil))
    }

    func testSearchQueryCapsLength() {
        let long = String(repeating: "长", count: 500)
        XCTAssertEqual(PreviewTextView.searchQuery(from: long)?.count, 100)
    }
}
