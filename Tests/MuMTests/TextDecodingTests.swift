import CoreFoundation
import XCTest
@testable import MuM

/// 文本解码守卫：二进制必须被拒（审计 D-2），非 UTF-8 文本要带着原编码回来（D-9）。
final class TextDecodingTests: XCTestCase {

    private func withTempFile(_ data: Data, _ body: (URL) -> Void) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mum-decode-\(UUID().uuidString)")
        try! data.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        body(url)
    }

    func testUTF8Passes() {
        withTempFile(Data("# 标题\n正文。\n".utf8)) { url in
            let decoded = TextDecoding.decode(url: url)
            XCTAssertEqual(decoded?.text, "# 标题\n正文。\n")
            XCTAssertEqual(decoded?.encoding, .utf8)
        }
    }

    func testEmptyFilePasses() {
        withTempFile(Data()) { url in
            XCTAssertEqual(TextDecoding.decode(url: url)?.text, "")
        }
    }

    func testNULByteIsBinary() {
        // ZIP 头 + NUL：任何含 NUL 的内容都按二进制拒
        var data = Data([0x50, 0x4B, 0x03, 0x04])
        data.append(contentsOf: [UInt8](repeating: 0x41, count: 100))
        data.append(0)
        withTempFile(data) { url in
            XCTAssertNil(TextDecoding.decode(url: url), "含 NUL 必须判定为二进制")
        }
    }

    func testControlCharGarbageIsBinary() {
        // 没有 NUL 但满地 C0 控制符：Latin-1 能"解"出来的东西也要被拒
        var data = Data()
        for _ in 0..<50 {
            data.append(contentsOf: [0x01, 0x02, 0x03, 0x41])
        }
        withTempFile(data) { url in
            XCTAssertNil(TextDecoding.decode(url: url), "控制字符占比过高必须判定为二进制")
        }
    }

    func testGBKTextKeepsItsEncoding() {
        let gbk = String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))
        let original = "# 中文标题\n\n这是一段 GBK 编码的正文，带标点：，。！\n"
        let data = original.data(using: gbk)!
        withTempFile(data) { url in
            let decoded = TextDecoding.decode(url: url)
            XCTAssertEqual(decoded?.text, original, "GBK 文本要原样解出，不能有替换字符")
            XCTAssertNotEqual(decoded?.encoding, .utf8, "编码要如实带回来，保存时写回同一种")
        }
    }

    func testLatin1TextPasses() {
        let data = "café au lait\n".data(using: .isoLatin1)!
        withTempFile(data) { url in
            XCTAssertEqual(TextDecoding.decode(url: url)?.text, "café au lait\n")
        }
    }
}
