import Foundation
import CoreFoundation

/// 文本文件的统一解码入口。
///
/// 所有"读文件进编辑器"的路径都必须走这里，不许自己 `String(contentsOf:)` ——
/// 只有这里做了二进制判定。判定规则（审计 D-2）：
///
/// - 全文有 NUL 字节 → 二进制（文本编码不会产出 NUL，没有例外）；
/// - UTF-8 → GB18030 → Latin-1 顺序尝试，每一档都要过各自的校验；
/// -  Latin-1 能把**任何**字节一一映射成字符，本身永不失败 —— 所以它的结果
///   还要过控制字符占比嗅探，过不去就拒。没有这道闸，`cp foo.zip x.svgz`
///   就能以乱码进编辑器，再被一次 UTF-8 保存毁掉原文件。
///
/// 不用 `NSString(contentsOf:usedEncoding:)` 的系统探测：它会把 GBK 字节
/// 误判成单字节编码，产出无 U+FFFD 的乱码，连嗅探都拦不住（D-9 回归测试）。
enum TextDecoding {

    /// 解码结果带着实际使用的编码：保存时要写回**同一种**，
    /// 不能把用户的 GBK 文件悄悄转成 UTF-8（审计 D-9）。
    struct Decoded {
        let text: String
        let encoding: String.Encoding
    }

    /// GB 18030（GBK 的超集）。macOS 的 String.Encoding 没有现成常量，从 CF 转。
    private static let gb18030 = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(
            CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue)))

    static func decode(url: URL) -> Decoded? {
        guard let data = try? Data(contentsOf: url) else { return nil }

        if data.contains(0) { return nil }

        // UTF-8 也要过嗅探：纯控制字符流是合法 UTF-8，但它就是二进制。
        // 命中即拒，不再下探 —— 下探到 Latin-1 只会得到"能解码"的假象。
        if let text = String(data: data, encoding: .utf8) {
            return looksLikeBinary(text) ? nil : Decoded(text: text, encoding: .utf8)
        }

        // GB18030 用往返校验：能解码不算数，能原样编码回同一份字节才算猜对。
        // 双字节编码的容错率极低，真 GBK 数据必过，随机字节几乎必挂。
        if let text = String(data: data, encoding: gb18030),
           text.data(using: gb18030) == data,
           !looksLikeBinary(text) {
            return Decoded(text: text, encoding: gb18030)
        }

        if let text = String(data: data, encoding: .isoLatin1), !looksLikeBinary(text) {
            return Decoded(text: text, encoding: .isoLatin1)
        }
        return nil
    }

    /// 控制字符（除 \t \n \r 与常见转义）占比超过 1% 就按二进制看。
    /// 文本几乎不含 C0/C1 控制符；二进制被强行解码后满地都是。
    private static func looksLikeBinary(_ text: String) -> Bool {
        let scalars = text.unicodeScalars
        guard !scalars.isEmpty else { return false }
        var controls = 0
        for scalar in scalars {
            let v = scalar.value
            if v < 0x20, v != 0x09, v != 0x0A, v != 0x0D {
                controls += 1
            } else if (0x7F...0x9F).contains(v) {
                controls += 1
            }
        }
        return Double(controls) / Double(scalars.count) > 0.01
    }
}
