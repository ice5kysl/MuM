import XCTest
@testable import MuM

/// CSV/TSV → Markdown 表格的解析与转义测试。
/// 这张表决定「用户打开 csv 看到的是表格还是一坨」，错一格整表就不渲染。
final class DelimitedTableTests: XCTestCase {

    func testBasicCSV() {
        let md = DelimitedTable.markdown(from: "name,age\nice,3\nkimi,1\n", delimiter: ",")
        XCTAssertEqual(md, """
        | name | age |
        | --- | --- |
        | ice | 3 |
        | kimi | 1 |
        """)
    }

    func testQuotedFieldWithCommaAndQuote() {
        let md = DelimitedTable.markdown(from: "a,b\n\"x,y\",\"say \"\"hi\"\"\"\n", delimiter: ",")
        XCTAssertEqual(md, """
        | a | b |
        | --- | --- |
        | x,y | say "hi" |
        """)
    }

    func testNewlineInsideQuotesFlattened() {
        let md = DelimitedTable.markdown(from: "a,b\n\"line1\nline2\",z\n", delimiter: ",")
        XCTAssertTrue(md?.contains("| line1 line2 | z |") == true)
    }

    func testPipeEscaped() {
        let md = DelimitedTable.markdown(from: "a,b\nx|y,\\back\n", delimiter: ",")
        XCTAssertTrue(md?.contains("| x\\|y | \\\\back |") == true)
    }

    func testTSV() {
        let md = DelimitedTable.markdown(from: "a\tb\n1\t2\n", delimiter: "\t")
        XCTAssertTrue(md?.hasPrefix("| a | b |\n") == true)
        XCTAssertTrue(md?.contains("| 1 | 2 |") == true)
    }

    func testRaggedRowsPaddedAndTruncated() {
        let md = DelimitedTable.markdown(from: "a,b,c\n1\n2,3,4,5,6\n", delimiter: ",")
        XCTAssertEqual(md, """
        | a | b | c |
        | --- | --- | --- |
        | 1 |  |  |
        | 2 | 3 | 4 |
        """)
    }

    func testNotTableCasesReturnNil() {
        XCTAssertNil(DelimitedTable.markdown(from: "", delimiter: ","))
        XCTAssertNil(DelimitedTable.markdown(from: "just one row,a\n", delimiter: ","), "只有表头没有数据行，不成表")
        XCTAssertNil(DelimitedTable.markdown(from: "a\nb\nc\n", delimiter: ","), "单列不是表")
    }

    func testRowCap() {
        var text = "a,b\n"
        for i in 0...DelimitedTable.maxRows { text += "\(i),x\n" }
        XCTAssertNil(DelimitedTable.markdown(from: text, delimiter: ","), "超行数上限退回纯文本")
    }

    func testCRLF() {
        let md = DelimitedTable.markdown(from: "a,b\r\n1,2\r\n", delimiter: ",")
        XCTAssertEqual(md, """
        | a | b |
        | --- | --- |
        | 1 | 2 |
        """)
    }
}
