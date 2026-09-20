import Foundation

/// CSV / TSV → Markdown 表格的转换器。
///
/// 为什么不直接建 NSTextTable：MarkdownRenderer 的表格排版（边框、表头底色、
/// 中文对齐）是手工调过的，转成 Markdown 喂给它，csv 文件白拿同一套版式 ——
/// 人也看到的和导出的一致。
///
/// 解析按 RFC 4180：引号字段、双引号转义（""）、字段内换行都处理；
/// TSV 走同一个状态机，分隔符换成制表符。
enum DelimitedTable {

    /// 行数上限：一张表全进一个 NSTextTable，行数无界会把排版压垮。
    /// 超了就退回纯文本呈现 —— 内容完整可见，比截断成"半张表"诚实。
    static let maxRows = 5000

    /// 把 CSV/TSV 文本转成 GFM 表格 Markdown。
    /// 返回 nil 表示不该按表格渲染（空、无分隔符、超行数上限）—— 调用方退回纯文本。
    static func markdown(from text: String, delimiter: Character) -> String? {
        let rows = parse(text, delimiter: delimiter)
        guard rows.count >= 2, rows.count <= maxRows else { return nil }

        let columnCount = rows[0].count
        guard columnCount >= 2 else { return nil } // 单列不是表，按纯文本读更舒服

        var lines: [String] = []
        lines.append(markdownRow(rows[0], columns: columnCount))
        lines.append("|" + String(repeating: " --- |", count: columnCount))
        for row in rows.dropFirst() {
            lines.append(markdownRow(row, columns: columnCount))
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - 解析（RFC 4180 状态机）

    /// 逐标量扫描。引号内的一切（含分隔符和换行）都是字段内容；
    /// `""` 是字面双引号。字段内换行在 Markdown 单元格里活不了，转成空格。
    ///
    /// 必须走 `unicodeScalars` 而不是直接迭代 String：Swift 的 Character 把
    /// `\r\n` 当成一个字符（grapheme cluster），`c == "\r"` 和 `c == "\n"`
    /// 都不匹配 —— CRLF 文件会被解析成一坨（测试 testCRLF 抓的就是这个）。
    static func parse(_ text: String, delimiter: Character) -> [[String]] {
        guard let delim = delimiter.unicodeScalars.first else { return [] }
        let scalars = text.unicodeScalars

        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var fieldStarted = false // 区分「空字段」和「引号包裹的空字段」无所谓，但要区分行尾

        var i = scalars.startIndex
        while i < scalars.endIndex {
            let c = scalars[i]
            if inQuotes {
                if c == "\"" {
                    let next = scalars.index(after: i)
                    if next < scalars.endIndex, scalars[next] == "\"" {
                        field.append("\"")
                        i = scalars.index(after: next)
                        continue
                    }
                    inQuotes = false
                } else if c == "\n" || c == "\r" {
                    field.append(" ")
                } else {
                    field.append(Character(c))
                }
            } else if c == "\"" {
                // 引号只在字段开头有意义；字段中间的引号按字面字符收
                if field.isEmpty, !fieldStarted {
                    inQuotes = true
                    fieldStarted = true
                } else {
                    field.append(Character(c))
                }
            } else if c == delim {
                row.append(field)
                field = ""
                fieldStarted = false
            } else if c == "\n" || c == "\r" {
                // \r\n 当成一个换行
                if c == "\r" {
                    let next = scalars.index(after: i)
                    if next < scalars.endIndex, scalars[next] == "\n" { i = next }
                }
                row.append(field)
                field = ""
                fieldStarted = false
                rows.append(row)
                row = []
            } else {
                field.append(Character(c))
                fieldStarted = true
            }
            i = scalars.index(after: i)
        }
        // 收尾：文件末尾无换行的最后一行
        if !field.isEmpty || fieldStarted || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        // 去掉末尾全空行（文件以换行结尾时 parse 不会多出行，这里只防连续空行尾巴）
        while let last = rows.last, last.allSatisfy({ $0.isEmpty }) {
            rows.removeLast()
        }
        return rows
    }

    // MARK: - Markdown 转义

    /// GFM 单元格：管道符必须转义，反斜杠先转义（顺序不能反），换行已在上游压平
    private static func escapeCell(_ field: String) -> String {
        field
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
    }

    /// 行与表头列数对齐：少了补空，多了截断 —— 真实 csv 常有不齐的行，
    /// 不齐时 GFM 整表直接不渲染，那比截断糟糕得多
    private static func markdownRow(_ row: [String], columns: Int) -> String {
        var cells = row.prefix(columns).map(escapeCell)
        while cells.count < columns { cells.append("") }
        return "| " + cells.joined(separator: " | ") + " |"
    }
}
