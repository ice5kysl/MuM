import XCTest
import AppKit
@testable import MuM

/// Services 入口（Finder 右键文件夹 →「服务」→「用 MuM 打开」）。
///
/// 这条链路的两端都在 app 之外：声明在 `Info.plist`（系统读），调用由系统发起。
/// 所以测试钉的是**我们这侧能守的三件事** —— pasteboard 的解析形状、声明的 UTI 范围、
/// 以及标题在英文表里真的存在。系统那半边只能靠真机点一遍（见 T-1 验收 8）。
final class ServicesTests: XCTestCase {

    private var repoRoot: URL {
        // Tests/MuMTests/ServicesTests.swift → MuMTests → Tests → 仓库根
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }

    /// 隔离的命名 pasteboard，不碰系统剪贴板
    private func makePasteboard(with urls: [NSURL] = []) -> NSPasteboard {
        let pb = NSPasteboard(name: NSPasteboard.Name("MuM.services.tests.\(UUID().uuidString)"))
        pb.clearContents()
        if !urls.isEmpty {
            XCTAssertTrue(pb.writeObjects(urls as [NSPasteboardWriting]), "写入测试 pasteboard 失败")
        }
        return pb
    }

    private func temporaryFolder() throws -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("mum-services-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    // MARK: - pasteboard 解析

    func testReadsSingleFolderURL() throws {
        let dir = try temporaryFolder()
        defer { try? FileManager.default.removeItem(at: dir) }

        let urls = AppDelegate.fileURLs(from: makePasteboard(with: [dir as NSURL]))
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls.first?.standardizedFileURL, dir.standardizedFileURL)
    }

    /// 多选是整个功能的常见用法（一次把几个项目都拉进来），顺序要保住
    func testReadsMultipleFoldersInSelectionOrder() throws {
        let a = try temporaryFolder()
        let b = try temporaryFolder()
        defer {
            try? FileManager.default.removeItem(at: a)
            try? FileManager.default.removeItem(at: b)
        }

        let urls = AppDelegate.fileURLs(from: makePasteboard(with: [a as NSURL, b as NSURL]))
        XCTAssertEqual(urls.map(\.standardizedFileURL), [a.standardizedFileURL, b.standardizedFileURL])
    }

    /// 服务声明里也含 public.text / public.source-code：其它应用里选中一个文件交给 MuM 打开
    func testReadsFileURL() throws {
        let file = FileManager.default.temporaryDirectory
            .appendingPathComponent("mum-services-\(UUID().uuidString).md")
        try "# 标题\n".write(to: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: file) }

        let urls = AppDelegate.fileURLs(from: makePasteboard(with: [file as NSURL]))
        XCTAssertEqual(urls.count, 1)
        XCTAssertEqual(urls.first?.standardizedFileURL, file.standardizedFileURL)
    }

    func testIgnoresNonFileURL() {
        let pb = makePasteboard(with: [URL(string: "https://example.com/a.md")! as NSURL])
        XCTAssertTrue(AppDelegate.fileURLs(from: pb).isEmpty, "只收文件 URL —— 网络 URL 没有本地文件可开")
    }

    func testEmptyPasteboardYieldsNothing() {
        XCTAssertTrue(AppDelegate.fileURLs(from: makePasteboard()).isEmpty)
    }

    // MARK: - Info.plist 声明形状

    private func serviceDeclaration() throws -> [String: Any] {
        let plist = repoRoot.appendingPathComponent("Resources/Info.plist")
        let dict = try XCTUnwrap(NSDictionary(contentsOf: plist) as? [String: Any])
        let services = try XCTUnwrap(dict["NSServices"] as? [[String: Any]], "Info.plist 缺少 NSServices")
        XCTAssertEqual(services.count, 1, "目前只该有一个服务")
        return try XCTUnwrap(services.first)
    }

    private func serviceTitle() throws -> String {
        let service = try serviceDeclaration()
        let menuItem = try XCTUnwrap(service["NSMenuItem"] as? [String: Any])
        return try XCTUnwrap(menuItem["default"] as? String)
    }

    func testServiceMessageMatchesSelector() throws {
        let service = try serviceDeclaration()
        XCTAssertEqual(
            service["NSMessage"] as? String, "openWithMuM",
            "NSMessage 必须对得上 AppDelegate 的 selector，否则系统找不到实现（点了没反应）"
        )
        XCTAssertEqual(service["NSPortName"] as? String, "MuM", "NSPortName 必须是 app 名（CFBundleName）")
        XCTAssertFalse(try serviceTitle().isEmpty)
    }

    /// 文件夹是这条服务的由来；同时钉住**不许**放宽到过宽的 UTI
    func testServiceFileTypesCoverFoldersButStayNarrow() throws {
        let service = try serviceDeclaration()
        let types = try XCTUnwrap(service["NSSendFileTypes"] as? [String])
        XCTAssertTrue(types.contains("public.folder"), "右键文件夹是这条服务的起点")

        for banned in ["public.item", "public.data", "public.content"] {
            XCTAssertFalse(
                types.contains(banned),
                "过宽的 UTI（\(banned)）会让右键 .app / .dmg 也冒出「用 MuM 打开」——这是噪音，不是功能"
            )
        }
    }

    // MARK: - 文案（跨文件一致性）

    /// Info.plist 的标题会被系统当作 key 去查 **`ServicesMenu.strings`**
    /// —— 不是 Localizable.strings，也不是 InfoPlist.strings。
    /// 0.8.2 放错了文件，英文系统下这一项回退成了中文（ice 报「语言对么」）。
    func testServiceTitleExistsInServicesMenuTable() throws {
        let title = try serviceTitle()
        let tableURL = repoRoot.appendingPathComponent("Resources/L10n/ServicesMenu.strings")
        let table = try XCTUnwrap(
            NSDictionary(contentsOf: tableURL) as? [String: String],
            "读不到 ServicesMenu.strings：\(tableURL.path)"
        )
        XCTAssertNotNil(
            table[title],
            "Info.plist 的 Services 标题「\(title)」不在 ServicesMenu.strings 里 —— 英文系统会显示中文"
        )
    }

    /// 系统查的是 `<lang>.lproj/ServicesMenu.strings`，build-app.sh 必须把它拷进去
    /// —— 光有源文件不够，打包漏拷同样会让英文系统显示中文
    func testBuildScriptCopiesServicesMenuTable() throws {
        let script = try String(
            contentsOf: repoRoot.appendingPathComponent("scripts/build-app.sh"),
            encoding: .utf8
        )
        XCTAssertTrue(
            script.contains("en.lproj/ServicesMenu.strings"),
            "build-app.sh 没有把 ServicesMenu.strings 拷进 en.lproj/ —— 服务标题会退回中文"
        )
    }

    func testErrorCopyIsTranslated() {
        L10n.override = .english
        defer { L10n.override = .system }
        XCTAssertEqual(L10n.t("没有可打开的文件"), "No files to open")
        XCTAssertFalse(
            L10n.missingKeys.contains("没有可打开的文件"),
            "缺英文会在 EN 模式下漏出中文"
        )
    }
}
