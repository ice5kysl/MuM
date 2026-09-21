import Foundation

/// 文件类型识别。决定点击文件后用哪种方式呈现：
/// Markdown 走「源码 + 渲染预览」，代码/纯文本走编辑器，图片与 PDF 走原生预览。
enum FileKind {
    case markdown
    case code
    case plainText
    /// RTF：能渲染（NSAttributedString 原生支持），但**不能当文本编辑** ——
    /// 编辑后保存会把纯文本盖在 RTF 控制字上，文件就毁了。只读。
    case richText
    case image
    case pdf
    case unsupported
    case folder

    // MARK: - 扩展名表

    private static let markdownExtensions: Set<String> = [
        "md", "markdown", "mdown", "mkd", "mkdn", "mdwn", "mdx", "ronn",
    ]

    private static let imageExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "webp", "bmp", "tif", "tiff", "heic", "heif", "icns", "ico", "svg",
    ]

    /// 可当文本打开的代码类扩展名 → 语法高亮语言标识。
    /// 注意 html/htm/xhtml 故意不在表里：.html 文件（打印导出、网页存档）的读者
    /// 要的是渲染后的页面，MuM 没有 Web 引擎也不追浏览器 —— 归「不支持的格式」，
    /// 导向页一键交给 Safari（ice 拍板，比看源码干净）。vue/svelte 是组件源码，留下。
    private static let codeExtensions: [String: String] = [
        "swift": "swift",
        "js": "javascript", "mjs": "javascript", "cjs": "javascript", "jsx": "javascript",
        "ts": "typescript", "tsx": "typescript",
        "py": "python", "pyw": "python",
        "rb": "ruby", "rake": "ruby", "gemspec": "ruby",
        "go": "go",
        "rs": "rust",
        "java": "java", "kt": "kotlin", "kts": "kotlin", "scala": "scala",
        "c": "c", "h": "c", "cc": "cpp", "cpp": "cpp", "cxx": "cpp", "hpp": "cpp", "hh": "cpp", "m": "objc", "mm": "objc",
        "cs": "csharp",
        "php": "php",
        "pl": "perl", "pm": "perl",
        "lua": "lua",
        "r": "r",
        "dart": "dart",
        "ex": "elixir", "exs": "elixir", "erl": "erlang",
        "hs": "haskell",
        "clj": "clojure", "cljs": "clojure",
        "zig": "zig",
        "sh": "shell", "bash": "shell", "zsh": "shell", "fish": "shell",
        "ps1": "powershell",
        "sql": "sql",
        "css": "css", "scss": "scss", "sass": "scss", "less": "less",
        "json": "json", "jsonc": "json", "json5": "json",
        "yaml": "yaml", "yml": "yaml",
        "toml": "toml", "ini": "ini", "cfg": "ini", "conf": "ini",
        "xml": "xml", "plist": "xml", "svgz": "xml",
        "vue": "html", "svelte": "html",
        "proto": "proto",
        "gradle": "groovy",
        "dockerfile": "docker",
        "makefile": "make", "mk": "make",
        "cmake": "cmake",
        "tf": "hcl", "hcl": "hcl",
        "graphql": "graphql", "gql": "graphql",
        "diff": "diff", "patch": "diff",
        "ipynb": "json",
    ]

    private static let plainTextExtensions: Set<String> = [
        "txt", "text", "log", "csv", "tsv", "tex", "bib",
        "vcf", "ics",
        "gitignore", "env", "editorconfig", "npmrc", "lock",
    ]

    // MARK: - 识别

    init(url: URL, isDirectory: Bool) {
        guard !isDirectory else { self = .folder; return }

        let ext = url.pathExtension.lowercased()
        let name = url.lastPathComponent.lowercased()

        if FileKind.markdownExtensions.contains(ext) {
            self = .markdown
        } else if FileKind.imageExtensions.contains(ext) {
            self = .image
        } else if ext == "pdf" {
            self = .pdf
        } else if ext == "rtf" {
            self = .richText
        } else if FileKind.codeExtensions[ext] != nil {
            self = .code
        } else if FileKind.plainTextExtensions.contains(ext) {
            self = .plainText
        } else if FileKind.isWellKnownTextFilename(name) {
            self = .plainText
        } else if ext.isEmpty && FileKind.looksLikeText(url) {
            // 无扩展名（Makefile / Dockerfile / LICENSE 之类）
            self = .plainText
        } else {
            self = .unsupported
        }
    }

    private static func isWellKnownTextFilename(_ name: String) -> Bool {
        let known: Set<String> = [
            "makefile", "dockerfile", "license", "licence", "readme", "changelog",
            "authors", "contributing", "notice", "gemfile", "rakefile", "procfile",
            "brewfile", "justfile", "cmakelists.txt",
        ]
        return known.contains(name)
    }

    /// 无扩展名文件用「前 8KB 是否含 NUL 字节」判断是不是文本。
    private static func looksLikeText(_ url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 8192), !data.isEmpty else { return false }
        return !data.contains(0)
    }

    // MARK: - 属性

    /// 能否作为文本在编辑器里打开
    var isTextual: Bool {
        switch self {
        case .markdown, .code, .plainText: return true
        default: return false
        }
    }

    /// 语法高亮用的语言标识，nil 表示不高亮
    static func language(for url: URL) -> String? {
        let ext = url.pathExtension.lowercased()
        if let lang = codeExtensions[ext] { return lang }

        switch url.lastPathComponent.lowercased() {
        case "makefile", "gnumakefile", "rakefile": return "make"
        case "dockerfile", "containerfile": return "docker"
        case "gemfile", "brewfile", "podfile", "fastfile", "vagrantfile": return "ruby"
        default: return nil
        }
    }

    /// 分隔表格的分隔符（csv / tsv），其余文件 nil。
    /// 这类文件编辑时仍是纯文本，只有 Read/Preview 的渲染走表格。
    static func tableDelimiter(for url: URL) -> Character? {
        switch url.pathExtension.lowercased() {
        case "csv": return ","
        case "tsv": return "\t"
        default: return nil
        }
    }
}
