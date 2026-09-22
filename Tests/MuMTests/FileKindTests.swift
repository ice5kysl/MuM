import XCTest
@testable import MuM

/// FileKind 的扩展名识别表测试。
/// 这张表决定「点开一个文件用哪种方式呈现」，是最容易被用户看见的映射错误。
final class FileKindTests: XCTestCase {

    private func kind(_ path: String, isDirectory: Bool = false) -> FileKind {
        FileKind(url: URL(fileURLWithPath: path), isDirectory: isDirectory)
    }

    // MARK: - 扩展名识别

    func testMarkdownVariants() {
        for ext in ["md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdx", "ronn"] {
            XCTAssertEqual(kind("/tmp/doc.\(ext)"), .markdown, "扩展名 \(ext) 应识别为 markdown")
        }
    }

    func testExtensionCaseInsensitive() {
        XCTAssertEqual(kind("/tmp/README.MD"), .markdown)
        XCTAssertEqual(kind("/tmp/photo.PNG"), .image)
        XCTAssertEqual(kind("/tmp/Note.TXT"), .plainText)
    }

    func testImagePDFCodePlain() {
        for ext in ["png", "jpg", "jpeg", "webp", "svg", "heic"] {
            XCTAssertEqual(kind("/tmp/a.\(ext)"), .image, "扩展名 \(ext) 应识别为 image")
        }
        XCTAssertEqual(kind("/tmp/a.pdf"), .pdf)

        for ext in ["swift", "ts", "py", "vue", "zsh"] {
            XCTAssertEqual(kind("/tmp/a.\(ext)"), .code, "扩展名 \(ext) 应识别为 code")
        }
        for ext in ["txt", "log", "csv", "env"] {
            XCTAssertEqual(kind("/tmp/a.\(ext)"), .plainText, "扩展名 \(ext) 应识别为 plainText")
        }
    }

    func testUnsupportedExtension() {
        XCTAssertEqual(kind("/tmp/a.bin"), .unsupported)
        XCTAssertEqual(kind("/tmp/a.o"), .unsupported)
        // Office 三件套 / 压缩包 / 音视频：不在计划里，界面给系统工具导向
        for ext in ["docx", "xlsx", "pptx", "doc", "zip", "mp4", "mp3", "epub"] {
            XCTAssertEqual(kind("/tmp/a.\(ext)"), .unsupported, "\(ext) 应保持不支持")
        }
        // html：读者要的是渲染后的页面，归导向页交给 Safari（ice 拍板）；
        // vue / svelte 是组件源码，仍按代码打开
        for ext in ["html", "htm", "xhtml"] {
            XCTAssertEqual(kind("/tmp/a.\(ext)"), .unsupported, "\(ext) 应归导向页")
        }
        XCTAssertEqual(kind("/tmp/a.vue"), .code)
        XCTAssertEqual(kind("/tmp/a.svelte"), .code)
    }

    // MARK: - RTF / 笔记本 / 通讯录日历

    func testRichTextAndNewTextKinds() {
        // rtf 渲染成富文本但只读 —— 当纯文本编辑会在保存时毁掉控制字
        XCTAssertEqual(kind("/tmp/a.rtf"), .richText)
        XCTAssertFalse(kind("/tmp/a.rtf").isTextual)
        // ipynb 本质是 JSON，按代码打开带高亮
        XCTAssertEqual(kind("/tmp/a.ipynb"), .code)
        XCTAssertEqual(FileKind.language(for: URL(fileURLWithPath: "/tmp/a.ipynb")), "json")
        // vcf / ics 是纯文本格式
        XCTAssertEqual(kind("/tmp/a.vcf"), .plainText)
        XCTAssertEqual(kind("/tmp/a.ics"), .plainText)
        // 字幕家族是带时间轴的纯文本
        for ext in ["srt", "ass", "ssa", "vtt"] {
            XCTAssertEqual(kind("/tmp/a.\(ext)"), .plainText, "\(ext) 字幕应按纯文本打开")
        }
    }

    func testDirectoryAlwaysFolder() {
        XCTAssertEqual(kind("/tmp/some/dir.md", isDirectory: true), .folder)
    }

    // MARK: - 无扩展名的已知文件名

    func testWellKnownTextFilenames() {
        for name in ["Makefile", "Dockerfile", "LICENSE", "README", "Brewfile", "CMakeLists.txt"] {
            XCTAssertEqual(kind("/tmp/\(name)"), .plainText, "\(name) 应按已知文件名识别为纯文本")
        }
    }

    // MARK: - language(for:)

    func testLanguageMapping() {
        func lang(_ path: String) -> String? {
            FileKind.language(for: URL(fileURLWithPath: path))
        }
        XCTAssertEqual(lang("/tmp/a.ts"), "typescript")
        XCTAssertEqual(lang("/tmp/a.jsx"), "javascript")
        XCTAssertEqual(lang("/tmp/a.scss"), "scss")
        XCTAssertEqual(lang("/tmp/Makefile"), "make")
        XCTAssertEqual(lang("/tmp/Dockerfile"), "docker")
        XCTAssertEqual(lang("/tmp/Gemfile"), "ruby")
        XCTAssertNil(lang("/tmp/a.md"), "markdown 走渲染预览，不做代码高亮")
        XCTAssertNil(lang("/tmp/a.unknownext"))
    }

    // MARK: - 属性

    func testIsTextual() {
        XCTAssertTrue(kind("/tmp/a.md").isTextual)
        XCTAssertTrue(kind("/tmp/a.swift").isTextual)
        XCTAssertTrue(kind("/tmp/a.txt").isTextual)
        XCTAssertFalse(kind("/tmp/a.png").isTextual)
        XCTAssertFalse(kind("/tmp/a.pdf").isTextual)
        XCTAssertFalse(kind("/tmp/a.bin").isTextual)
        XCTAssertFalse(kind("/tmp/dir", isDirectory: true).isTextual)
    }
}
