import AppKit

/// Headless 子命令（给 agent 用）：`MuM render|outline|search|check …`
///
/// 三条硬约定：
///   1. 无窗口、无 Dock 图标、无 UI 激活 —— activationPolicy(.prohibited)，
///      每条命令前后各断言一次 NSApp.windows.isEmpty，结果打到 stderr。
///   2. --json 的机器格式走 stdout 且 stdout 只有 JSON；人读的诊断一律 stderr。
///      （非 --json 时，结果本身 —— 大纲树、grep 风格命中行 —— 走 stdout，
///       与 unix 工具一致；进度/汇总走 stderr。）
///   3. 退出码分类：0 成功 / 1 文件读不到 / 2 用法错误 / 3 渲染或编码失败 / 4 搜索无结果。
///
/// 渲染出图与应用内 ⌘⇧E 共用 DocumentRenderer —— agent 出的图就是用户看到的图。
enum Headless {

    static let subcommands: Set<String> = ["render", "outline", "search", "check"]

    /// 是 headless 子命令就执行并返回退出码；否则返回 nil，让 app 正常启动。
    /// 在 NSApplication.run() 之前调用（与 --selftest/--bench 同一先例）。
    static func run(arguments: [String]) -> Int32? {
        guard arguments.count > 1, subcommands.contains(arguments[1]) else { return nil }

        let app = NSApplication.shared
        app.setActivationPolicy(.prohibited)
        assertHeadless(app)

        let args = Args(Array(arguments.dropFirst(2)))
        let code: Int32
        switch arguments[1] {
        case "render": code = render(args)
        case "outline": code = outline(args)
        case "search": code = search(args)
        case "check": code = check(args)
        default: code = 2
        }

        assertHeadless(app)
        return code
    }

    /// 无窗口断言：任何一条命令都不该有窗口对象出现
    private static func assertHeadless(_ app: NSApplication) {
        let ok = app.windows.isEmpty
        err("[headless] windows=\(app.windows.count) policy=prohibited \(ok ? "✓" : "✗")")
    }

    // MARK: - render

    /// `MuM render <file.md> --png out.png [--width 780] [--theme <名>] [--dark]`
    /// `MuM render <file.md> --pdf out.pdf …`
    private static func render(_ args: Args) -> Int32 {
        guard let file = args.positional.first else {
            return usage("用法：MuM render <file.md> --png <out.png>|--pdf <out.pdf> [--width 780] [--theme system|paper|quiet|contrast] [--dark]")
        }
        let output: String
        if let path = args.flags["png"] { output = path }
        else if let path = args.flags["pdf"] { output = path }
        else {
            return usage("render 需要 --png <路径> 或 --pdf <路径>")
        }

        guard let text = read(file) else { return 1 }

        var options = DocumentRenderer.Options()
        if let width = args.flags["width"] {
            guard let value = Double(width), value >= 200 else {
                return usage("--width 需要 ≥200 的数字，收到：\(width)")
            }
            options.width = CGFloat(value)
        }
        if let name = args.flags["theme"] {
            guard let theme = parseTheme(name) else {
                return usage("未知主题：\(name)（可选 system|paper|quiet|contrast）")
            }
            options.readingTheme = theme
        }
        options.dark = args.bools.contains("dark")
        // 语义色按钉住的外观解析（同 SnapshotRenderer 的教训：不钉会解析跑偏）
        NSApp.appearance = NSAppearance(named: options.dark == true ? .darkAqua : .aqua)

        let input = URL(fileURLWithPath: file).standardizedFileURL
        let outputURL = URL(fileURLWithPath: output)
        do {
            try DocumentRenderer.write(
                text: text,
                kind: FileKind(url: input, isDirectory: false),
                baseURL: input.deletingLastPathComponent(),
                to: outputURL,
                options: options
            )
        } catch {
            err("渲染失败：\(error.localizedDescription)")
            return 3
        }

        let bytes = (try? FileManager.default.attributesOfItem(atPath: output)[.size] as? Int) ?? 0
        err("已渲染 \(input.lastPathComponent) → \(outputURL.lastPathComponent)（\(bytes) 字节）")
        return 0
    }

    // MARK: - outline

    /// `MuM outline <file.md> [--json]` —— 标题树
    private static func outline(_ args: Args) -> Int32 {
        guard let file = args.positional.first else {
            return usage("用法：MuM outline <file.md> [--json]")
        }
        guard let text = read(file) else { return 1 }

        let rendered = DocumentRenderer.render(
            text: text, kind: .markdown,
            baseURL: URL(fileURLWithPath: file).deletingLastPathComponent(),
            options: DocumentRenderer.Options()
        )

        if args.bools.contains("json") {
            printJSON(rendered.outline.map {
                ["level": $0.level, "title": $0.title, "location": $0.location] as [String: Any]
            })
        } else {
            for item in rendered.outline {
                print("\(String(repeating: "  ", count: item.level - 1))H\(item.level) \(item.title)")
            }
            err("共 \(rendered.outline.count) 条标题")
        }
        return 0
    }

    // MARK: - search

    /// `MuM search <query> [--json] [--root <dir>]...` —— 默认当前目录为一个 scope。
    /// 引擎与应用内 ⌘⇧F 是同一个（GlobalSearchEngine），规则与 grep -r 对齐。
    private static func search(_ args: Args) -> Int32 {
        guard let query = args.positional.first, !query.isEmpty else {
            return usage("用法：MuM search <query> [--json] [--root <dir>]...")
        }
        let roots = args.roots.isEmpty ? [FileManager.default.currentDirectoryPath] : args.roots
        for root in roots {
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: root, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                err("目录不存在：\(root)")
                return 1
            }
        }

        let scopes = roots.map {
            GlobalSearchEngine.Scope(
                root: URL(fileURLWithPath: $0).standardizedFileURL,
                name: URL(fileURLWithPath: $0).lastPathComponent
            )
        }

        // 引擎是后台扫描 + 主线程回调：跑一小段 runloop 直到 isFinished
        var hits: [GlobalSearchEngine.Hit] = []
        var scanned = 0
        var finished = false
        let engine = GlobalSearchEngine()
        engine.search(query: query, scopes: scopes) { batch in
            hits.append(contentsOf: batch.hits)
            scanned = batch.filesScanned
            if batch.isFinished { finished = true }
        }
        while !finished {
            RunLoop.main.run(until: Date().addingTimeInterval(0.01))
        }

        if args.bools.contains("json") {
            printJSON(hits.map { hit in
                [
                    "file": hit.fileURL.path,
                    "relativePath": hit.relativePath,
                    "kind": hit.kind == .content ? "content" : "fileName",
                    "line": hit.lineNumber,
                    "lineText": hit.lineText,
                    "occurrence": hit.occurrence,
                ] as [String: Any]
            })
        } else {
            for hit in hits {
                switch hit.kind {
                case .fileName:
                    print("\(hit.relativePath)（文件名命中）")
                case .content:
                    // grep 风格：路径:行号: 行内容
                    print("\(hit.relativePath):\(hit.lineNumber): \(hit.lineText)")
                }
            }
            err("共 \(hits.count) 条命中，扫描 \(scanned) 个文件")
        }
        return hits.isEmpty ? 4 : 0
    }

    // MARK: - check

    /// `MuM check <file.md> [--json]` —— 解析 + 渲染是否成功
    private static func check(_ args: Args) -> Int32 {
        guard let file = args.positional.first else {
            return usage("用法：MuM check <file.md> [--json]")
        }
        guard let text = read(file) else { return 1 }

        let input = URL(fileURLWithPath: file).standardizedFileURL
        let rendered = DocumentRenderer.render(
            text: text,
            kind: FileKind(url: input, isDirectory: false),
            baseURL: input.deletingLastPathComponent(),
            options: DocumentRenderer.Options()
        )
        // 渲染管线不抛异常：源非空而渲染结果为空才算失败
        guard !text.isEmpty ? rendered.attributed.length > 0 : true else {
            err("✗ 渲染结果为空：\(file)")
            return 3
        }

        if args.bools.contains("json") {
            printJSON([
                "ok": true,
                "file": input.path,
                "characters": text.count,
                "renderedLength": rendered.attributed.length,
                "outlineItems": rendered.outline.count,
                // 整数毫秒：JSONSerialization 会把 16.1 这类值打成 16.100000000000001，
                // 机器格式要的是稳定，不是小数点后的假精度
                "renderMS": Int(rendered.renderMS.rounded()),
            ] as [String: Any])
        } else {
            err(String(
                format: "✓ %@：%d 字符 → 渲染 %d 字符，%d 条标题，%.1f ms",
                input.lastPathComponent, text.count,
                rendered.attributed.length, rendered.outline.count, rendered.renderMS
            ))
        }
        return 0
    }

    // MARK: - 小工具

    private static func parseTheme(_ name: String) -> ReadingTheme? {
        switch name.lowercased() {
        case "system": return .system
        case "paper": return .paper
        case "quiet": return .quiet
        case "contrast": return .contrast
        default: return nil
        }
    }

    /// 读文件为文本。读不了（不存在 / 二进制 / 编码失败）打 stderr 并返回 nil。
    /// 用 TextDecoding 而不是 String(contentsOfFile:)：与应用打开文件的判定一致，
    /// 二进制文件不会渲染出一屏乱码。
    private static func read(_ path: String) -> String? {
        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard let decoded = TextDecoding.decode(url: url) else {
            err("读不到文件（不存在或不是文本）：\(path)")
            return nil
        }
        return decoded.text
    }

    /// 人读的一律 stderr
    private static func err(_ message: String) {
        FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
    }

    @discardableResult
    private static func usage(_ message: String) -> Int32 {
        err(message)
        return 2
    }

    /// --json 的唯一出口：prettyPrinted + sortedKeys，格式稳定可 diff
    private static func printJSON(_ value: Any) {
        guard JSONSerialization.isValidJSONObject(value),
              let data = try? JSONSerialization.data(
                  withJSONObject: value, options: [.prettyPrinted, .sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            err("JSON 编码失败")
            return
        }
        print(string)
    }

    /// 手工参数解析：`--key value` 收进 flags，可重复的 --root 单列，
    /// --json/--dark 这类布尔进 bools，其余按位置参数
    private struct Args {
        var positional: [String] = []
        var flags: [String: String] = [:]
        var bools: Set<String> = []
        var roots: [String] = []

        init(_ argv: [String]) {
            var index = 0
            while index < argv.count {
                let argument = argv[index]
                guard argument.hasPrefix("--") else {
                    positional.append(argument)
                    index += 1
                    continue
                }
                let key = String(argument.dropFirst(2))
                if key == "json" || key == "dark" {
                    bools.insert(key)
                    index += 1
                } else if key == "root" {
                    if index + 1 < argv.count {
                        roots.append(argv[index + 1])
                        index += 2
                    } else {
                        index += 1
                    }
                } else if index + 1 < argv.count {
                    flags[key] = argv[index + 1]
                    index += 2
                } else {
                    bools.insert(key)
                    index += 1
                }
            }
        }
    }
}
