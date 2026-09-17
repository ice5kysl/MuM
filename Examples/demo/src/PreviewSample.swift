import AppKit

/// 代码文件也走预览面板，整篇做语法高亮，方便快速翻阅。
/// 这个文件同时用来验证 .swift 文件在文件树里点击后的表现。
struct PreviewSample {
    let title: String
    let lines: Int

    static let example = PreviewSample(title: "MuM", lines: 42)

    func describe() -> String {
        "\(title) 共 \(lines) 行"
    }
}

enum SampleError: Error {
    case notImplemented
}

func load() throws -> PreviewSample {
    // 行注释
    /* 块注释
       可以跨多行 */
    let samples = [1, 2, 3].map { $0 * 2 }
    guard !samples.isEmpty else { throw SampleError.notImplemented }
    return PreviewSample(title: "samples", lines: samples.count)
}
