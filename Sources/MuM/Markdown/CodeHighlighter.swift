import AppKit

/// 轻量语法高亮。
///
/// 刻意不引入 tree-sitter 或 TextMate 语法：那些方案要么带 C 依赖、要么需要
/// 正则编译开销，而预览区只需要「代码块看起来有层次」这一个目标。这里用一次
/// O(n) 字符扫描完成，没有正则、没有回溯，几万行代码块也不会拖慢预览刷新。
enum CodeHighlighter {

    static func highlight(_ code: String, language: String?, theme: MarkdownTheme) -> NSAttributedString {
        let attributed = NSMutableAttributedString(string: code, attributes: [
            .font: theme.codeBlockFont,
            .foregroundColor: theme.codeTextColor,
        ])

        guard let language, let rules = LanguageRules.rules(for: language) else {
            return attributed
        }

        let scalars = Array(code.utf16)
        let n = scalars.count
        var i = 0

        func paint(_ start: Int, _ end: Int, _ color: NSColor) {
            guard end > start, start >= 0, end <= n else { return }
            attributed.addAttribute(.foregroundColor, value: color, range: NSRange(location: start, length: end - start))
        }

        while i < n {
            let c = scalars[i]

            // 行注释
            if let prefix = rules.lineComment.first(where: { matches(scalars, at: i, pattern: $0) }) {
                let start = i
                i += prefix.utf16.count
                while i < n && scalars[i] != 0x0A { i += 1 }
                paint(start, i, rules.commentColor(theme))
                continue
            }

            // 块注释
            if let pair = rules.blockComment.first(where: { matches(scalars, at: i, pattern: $0.0) }) {
                let start = i
                i += pair.0.utf16.count
                while i < n && !matches(scalars, at: i, pattern: pair.1) { i += 1 }
                i = min(n, i + pair.1.utf16.count)
                paint(start, i, rules.commentColor(theme))
                continue
            }

            // 字符串
            if rules.stringDelimiters.contains(c), let end = scanString(scalars, from: i, delimiter: c, rules: rules) {
                paint(i, end, theme.syntaxString)
                i = end
                continue
            }

            // 数字
            if isDigit(c) {
                let start = i
                i += 1
                while i < n, isDigit(scalars[i]) || scalars[i] == 0x2E || scalars[i] == 0x5F
                    || (scalars[i] | 0x20) == 0x78 /* x */ || isHexLetter(scalars[i]) {
                    i += 1
                }
                paint(start, i, theme.syntaxNumber)
                continue
            }

            // 标识符：关键字 / 类型 / 函数 / 常量
            if isIdentStart(c) {
                let start = i
                i += 1
                while i < n, isIdentPart(scalars[i]) { i += 1 }
                let word = String(utf16CodeUnits: Array(scalars[start..<i]), count: i - start)

                if rules.keywords.contains(word) {
                    paint(start, i, theme.syntaxKeyword)
                } else if rules.types.contains(word) {
                    paint(start, i, theme.syntaxType)
                } else if rules.constants.contains(word) {
                    paint(start, i, theme.syntaxConstant)
                } else if nextNonSpace(scalars, from: i) == 0x28 /* ( */ {
                    paint(start, i, theme.syntaxFunction)
                }
                continue
            }

            i += 1
        }

        return attributed
    }

    // MARK: - 扫描辅助

    private static func scanString(_ s: [UInt16], from start: Int, delimiter: UInt16, rules: LanguageRules) -> Int? {
        let n = s.count
        var i = start + 1

        // 三引号字符串（Python / Kotlin 等）
        if rules.supportsTripleQuote, i + 1 < n, s[i] == delimiter, s[i + 1] == delimiter {
            i += 2
            while i + 2 < n {
                if s[i] == delimiter, s[i + 1] == delimiter, s[i + 2] == delimiter { return i + 3 }
                i += 1
            }
            return n
        }

        while i < n {
            let c = s[i]
            if c == 0x5C /* \ */ { i += 2; continue }
            if c == 0x0A && !rules.stringsSpanLines { return i }
            if c == delimiter { return i + 1 }
            i += 1
        }
        return n
    }

    private static func matches(_ s: [UInt16], at index: Int, pattern: String) -> Bool {
        let p = Array(pattern.utf16)
        guard index + p.count <= s.count else { return false }
        for (offset, unit) in p.enumerated() where s[index + offset] != unit { return false }
        return true
    }

    private static func nextNonSpace(_ s: [UInt16], from index: Int) -> UInt16? {
        var i = index
        while i < s.count {
            if s[i] != 0x20 && s[i] != 0x09 { return s[i] }
            i += 1
        }
        return nil
    }

    private static func isDigit(_ c: UInt16) -> Bool { c >= 0x30 && c <= 0x39 }
    private static func isHexLetter(_ c: UInt16) -> Bool { let l = c | 0x20; return l >= 0x61 && l <= 0x66 }
    private static func isLetter(_ c: UInt16) -> Bool { let l = c | 0x20; return l >= 0x61 && l <= 0x7A }
    private static func isIdentStart(_ c: UInt16) -> Bool { isLetter(c) || c == 0x5F || c == 0x24 }
    private static func isIdentPart(_ c: UInt16) -> Bool { isLetter(c) || isDigit(c) || c == 0x5F }
}

/// 每种语言的词法规则。数据驱动，加一门语言只是加一行。
struct LanguageRules {
    enum Flavor { case cLike, hashLike, markup, shell }

    var flavor: Flavor = .cLike
    var keywords: Set<String> = []
    var types: Set<String> = []
    var constants: Set<String> = []
    var lineComment: [String] = ["//"]
    var blockComment: [(String, String)] = [("/*", "*/")]
    var stringDelimiters: [UInt16] = [0x22, 0x27] // " '
    var stringsSpanLines = false
    var supportsTripleQuote = false

    func commentColor(_ theme: MarkdownTheme) -> NSColor { theme.syntaxComment }

    private static let cache = ConcurrentCache<LanguageRules>()

    static func rules(for language: String) -> LanguageRules? {
        let key = language.lowercased()
        if let cached = cache[key] { return cached }
        guard let rules = build(key) else { return nil }
        cache[key] = rules
        return rules
    }

    // MARK: - 语言表

    private static func build(_ name: String) -> LanguageRules? {
        switch name {
        case "swift":
            return cLike(
                keywords: "actor associatedtype async await break case catch class continue convenience default defer deinit do dynamic else enum extension fallthrough false fileprivate final for func get guard if import in indirect infix init inout internal is lazy let mutating nil nonisolated open operator optional override postfix precedence prefix private protocol public repeat required rethrows return self Self set some static struct subscript super switch throw throws true try typealias var weak where while yield",
                types: "Any AnyObject Array Bool Character Data Dictionary Double Error Float Int Int8 Int16 Int32 Int64 Never Optional Result Set String Substring UInt UInt8 UInt16 UInt32 UInt64 Void",
                constants: "true false nil self"
            )

        case "javascript", "typescript":
            var r = cLike(
                keywords: "as async await break case catch class const continue debugger default delete do else enum export extends finally for from function get if implements import in instanceof interface let new of package private protected public return set static super switch this throw try typeof var void while with yield type declare namespace abstract readonly satisfies keyof infer is",
                types: "Array Boolean Date Error Function JSON Map Math Number Object Promise Proxy RegExp Set String Symbol WeakMap WeakSet any unknown never void number string boolean object symbol bigint",
                constants: "true false null undefined NaN Infinity this super"
            )
            r.supportsTripleQuote = false
            return r

        case "python":
            var r = LanguageRules()
            r.flavor = .hashLike
            r.lineComment = ["#"]
            r.blockComment = []
            r.stringsSpanLines = false
            r.supportsTripleQuote = true
            r.keywords = Set("and as assert async await break class continue def del elif else except finally for from global if import in is lambda nonlocal not or pass raise return try while with yield match case".split(separator: " ").map(String.init))
            r.types = Set("bool bytes dict float frozenset int list object set str tuple type".split(separator: " ").map(String.init))
            r.constants = Set("True False None self cls NotImplemented Ellipsis".split(separator: " ").map(String.init))
            return r

        case "ruby":
            var r = LanguageRules()
            r.flavor = .hashLike
            r.lineComment = ["#"]
            r.blockComment = [("=begin", "=end")]
            r.keywords = Set("alias and begin break case class def defined? do else elsif end ensure for if in module next not or redo rescue retry return self super then undef unless until when while yield require require_relative attr_accessor attr_reader attr_writer include extend prepend raise lambda proc".split(separator: " ").map(String.init))
            r.types = Set("Array Hash String Symbol Integer Float Object Class Module Proc Range Struct".split(separator: " ").map(String.init))
            r.constants = Set("true false nil self __FILE__ __LINE__".split(separator: " ").map(String.init))
            return r

        case "go":
            return cLike(
                keywords: "break case chan const continue default defer else fallthrough for func go goto if import interface map package range return select struct switch type var",
                types: "bool byte complex64 complex128 error float32 float64 int int8 int16 int32 int64 rune string uint uint8 uint16 uint32 uint64 uintptr any",
                constants: "true false nil iota"
            )

        case "rust":
            var r = cLike(
                keywords: "as async await break const continue crate dyn else enum extern fn for if impl in let loop match mod move mut pub ref return self Self static struct super trait type unsafe use where while union",
                types: "bool char f32 f64 i8 i16 i32 i64 i128 isize str String u8 u16 u32 u64 u128 usize Vec Option Result Box Rc Arc HashMap HashSet",
                constants: "true false None Some Ok Err"
            )
            r.blockComment = [("/*", "*/")]
            return r

        case "java", "kotlin", "scala", "csharp", "dart", "groovy":
            return cLike(
                keywords: "abstract as assert async await break case catch class const continue data default do dynamic else enum export extends external false final finally for fun get if implements import in instanceof interface internal is let native new null object open operator out override package private protected public reified return sealed set static strictfp super switch synchronized this throw throws trait true try typealias typeof val var void volatile when where while yield var",
                types: "ArrayList Boolean Byte CharClass Character Double Exception Float HashMap HashSet Int IntArray Integer List Long Map MutableList MutableMap Number Object Optional Pair Set Short String StringBuilder Triple Unit Void BigDecimal BigInteger Delegate Duration",
                constants: "true false null this super it"
            )

        case "c", "cpp", "objc", "objective-c":
            return cLike(
                keywords: "alignas alignof auto break case catch class const constexpr continue decltype default delete do dynamic_cast else enum explicit export extern false for friend goto if inline mutable namespace new noexcept nullptr operator private protected public register reinterpret_cast return sizeof static static_assert static_cast struct switch template this thread_local throw true try typedef typeid typename union using virtual volatile while interface implementation end protocol property synthesize atomic copy nonatomic strong weak assign retain release autoreleasepool nil YES NO self super",
                types: "bool char char16_t char32_t double float int int8_t int16_t int32_t int64_t long short signed size_t uint8_t uint16_t uint32_t uint64_t unsigned void wchar_t id NSInteger NSUInteger CGFloat NSString NSArray NSDictionary NSObject",
                constants: "NULL nullptr true false nil YES NO"
            )

        case "shell", "bash", "zsh", "fish", "powershell":
            var r = LanguageRules()
            r.flavor = .shell
            r.lineComment = ["#"]
            r.blockComment = []
            r.keywords = Set("if then else elif fi for while until do done case esac function return in select time coproc break continue local export readonly declare typeset unset shift source alias echo printf cd pwd set trap exit".split(separator: " ").map(String.init))
            r.types = []
            r.constants = Set("true false".split(separator: " ").map(String.init))
            return r

        case "sql":
            var r = LanguageRules()
            r.flavor = .cLike
            r.lineComment = ["--"]
            r.blockComment = [("/*", "*/")]
            r.keywords = Set("select from where insert into values update set delete create table alter drop index view join left right inner outer full on group by order having limit offset union all distinct as and or not null is in between like exists case when then else end primary key foreign references default unique constraint cascade begin commit rollback transaction grant revoke truncate with recursive returning".split(separator: " ").map(String.init))
            r.types = Set("int integer bigint smallint serial text varchar char boolean date timestamp timestamptz time interval numeric decimal real double precision json jsonb uuid bytea array".split(separator: " ").map(String.init))
            r.constants = Set("true false null".split(separator: " ").map(String.init))
            return r

        case "html", "xml", "vue", "svelte":
            var r = LanguageRules()
            r.flavor = .markup
            r.lineComment = []
            r.blockComment = [("<!--", "-->")]
            r.keywords = []
            r.types = []
            r.constants = []
            return r

        case "css", "scss", "sass", "less":
            var r = LanguageRules()
            r.flavor = .cLike
            r.lineComment = ["//"]
            r.blockComment = [("/*", "*/")]
            r.keywords = []
            r.types = []
            r.constants = Set("important inherit initial unset auto none block inline flex grid absolute relative fixed sticky".split(separator: " ").map(String.init))
            return r

        case "json", "jsonc", "json5":
            var r = LanguageRules()
            r.flavor = .cLike
            r.lineComment = name == "json" ? [] : ["//"]
            r.blockComment = name == "json" ? [] : [("/*", "*/")]
            r.keywords = []
            r.types = []
            r.constants = Set(["true", "false", "null"])
            return r

        case "yaml", "yml", "toml", "ini", "cfg", "conf", "editorconfig":
            var r = LanguageRules()
            r.flavor = .hashLike
            r.lineComment = ["#"]
            r.blockComment = []
            r.keywords = []
            r.types = []
            r.constants = Set(["true", "false", "null", "yes", "no", "on", "off", "~"])
            return r

        case "make", "docker", "cmake", "ini-conf":
            var r = LanguageRules()
            r.flavor = .hashLike
            r.lineComment = ["#"]
            r.blockComment = []
            r.keywords = Set("FROM RUN CMD ENTRYPOINT COPY ADD ENV ARG WORKDIR EXPOSE VOLUME USER HEALTHCHECK SHELL LABEL ONBUILD STOPSIGNAL if else endif define endef include project cmake_minimum_required add_executable add_library target_link_libraries find_package set list".split(separator: " ").map(String.init))
            r.types = []
            r.constants = []
            return r

        case "diff", "patch":
            var r = LanguageRules()
            r.flavor = .cLike
            r.lineComment = []
            r.blockComment = []
            r.keywords = []
            r.types = []
            r.constants = []
            return r

        case "markdown", "md":
            var r = LanguageRules()
            r.flavor = .markup
            r.lineComment = []
            r.blockComment = [("<!--", "-->")]
            r.keywords = []
            r.types = []
            r.constants = []
            return r

        default:
            // 未知语言：给一套 C 系规则兜底，至少注释和字符串会着色
            return cLike(keywords: "", types: "", constants: "true false null")
        }
    }

    private static func cLike(keywords: String, types: String, constants: String) -> LanguageRules {
        var r = LanguageRules()
        r.flavor = .cLike
        r.keywords = Set(keywords.split(separator: " ").map(String.init))
        r.types = Set(types.split(separator: " ").map(String.init))
        r.constants = Set(constants.split(separator: " ").map(String.init))
        return r
    }
}
