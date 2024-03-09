import Lua
import LibC

extension StringProtocol {
    func count(of char: Character) -> Int {
        var n = 0
        for c in self {
            if c == char {
                n += 1
            }
        }
        return n
    }
}

internal struct LuaLexer {
    internal enum Operator: String {
        case and = "and"
        case or = "or"
        case add = "+"
        case sub = "-"
        case mul = "*"
        case div = "/"
        case mod = "%"
        case pow = "^"
        case eq = "=="
        case ne = "~="
        case le = "<="
        case ge = ">="
        case lt = "<"
        case gt = ">"
        case concat = ".."
        case len = "#"
        case not = "not"
        case lparen = "("
        case rparen = ")"
        case lbrace = "{"
        case rbrace = "}"
        case lbracket = "["
        case rbracket = "]"
        case label = "::"
        case semicolon = ";"
        case colon = ":"
        case comma = ","
        case dot = "."
        case assign = "="
    }

    internal enum Constant: String {
        case `false` = "false"
        case `true` = "true"
        case `nil` = "nil"
        case vararg = "..."
    }

    internal enum Keyword: String {
        case `break` = "break"
        case `do` = "do"
        case `else` = "else"
        case `elseif` = "elseif"
        case `end` = "end"
        case `for` = "for"
        case `function` = "function"
        case `goto` = "goto"
        case `if` = "if"
        case `in` = "in"
        case `local` = "local"
        case `repeat` = "repeat"
        case `return` = "return"
        case `then` = "then"
        case `until` = "until"
        case `while` = "while"
    }

    internal enum Token {
        case keyword(Keyword, line: Int)
        case constant(Constant, line: Int)
        case `operator`(Operator, line: Int)
        case name(String, line: Int)
        case string([UInt8], line: Int)
        case number(Double, line: Int)

        internal var text: String {
            switch self {
                case .keyword(let kw, _): return kw.rawValue
                case .constant(let k, _): return k.rawValue
                case .operator(let op, _): return op.rawValue
                case .name(let str, _): return str
                case .string(let str, _): return str.string
                case .number(let n, _): return String(n)
            }
        }

        internal var line: Int {
            switch self {
                case .keyword(_, let line): return line
                case .constant(_, let line): return line
                case .operator(_, let line): return line
                case .name(_, let line): return line
                case .string(_, let line): return line
                case .number(_, let line): return line
            }
        }
    }

    private static let classes: [String: [UInt8]] = [
        "operator": "^([;,%[%]%(%)%{%}%+%*/%^%%#&|])()",
        "minus": "^(%-)()[^%-]",
        "eq1": "^([=~<>])()[^=]",
        "eq2": "^([=~<>]=)()",
        "self": "^(:)()[^:]",
        "label": "^(::)()",
        "dot": "^(%.)()[^%.]",
        "concat": "^(%.%.)()[^%.]",
        "vararg": "^(%.%.%.)()",
        "name": "^([%a_][%w_]*)()[^%w_]",
        "number": "^(%d+%.?%d*)()[^%x%.eExXpP]",
        "decnumber": "^(%.?%d+)()[^%x%.eExXpP]",
        "scinumber": "^(%d+%.?%d*[eE][%+%-]?%d+)()[^%x%.eExXpP]",
        "decscinumber": "^(%.?%d+[eE][%+%-]?%d+)()[^%x%.eExXpP]",
        "hexnumber": "^(0[xX]%x+%.?%x*)()[^%x%.eExXpP]",
        "dechexnumber": "^(0[xX]%.?%x+)()[^%x%.eExXpP]",
        "scihexnumber": "^(0[xX]%.?%x+[pP][%+%-]?%x+)()[^%x%.eExXpP]",
        "decscihexnumber": "^(0[xX]%x+%.?%x*[pP][%+%-]?%x+)()[^%x%.eExXpP]",
        "linecomment": "^(%-%-[^\n]*)()[\n\0]",
        "blockcomment": "^(%-%-%[(=*)%[.-%]%2%])()",
        "emptyblockcomment": "^(%-%-%[(=*)%[%]%2%])()",
        "blockquote": "^(%[(=*)%[.-%]%2%])()",
        "emptyblockquote": "^(%[(=*)%[%]%2%])()",
        "dquote": "^(\"[^\"]*\")()",
        "squote": "^('[^']*')()",
        "whitespace": "^(%s+)()",
        "invalid": "^([^%w%s_;:=%.,%[%]%(%)%{%}%+%-%*/%^%%<>~#&|\"']+)()",
    ]

    private static let classes_precedence = [
        "name", "scihexnumber", "decscihexnumber", "hexnumber", "dechexnumber",
        "scinumber", "decscinumber", "number", "decnumber",
        "blockcomment", "emptyblockcomment", "linecomment", "blockquote", "emptyblockquote",
        "vararg", "concat", "label", "eq2", "eq1", "minus", "dot", "self", "operator",
        "dquote", "squote", "whitespace", "invalid"]
    
    private static let keywords = Set<[UInt8]>([
        "break", "do", "else", "elseif", "end", "for", "function", "goto", "if",
        "in", "local", "repeat", "return", "then", "until", "while"])
    
    private static let operators = Set<[UInt8]>([
        "and", "not", "or", "+", "-", "*", "/", "%", "^", "#", "==", "~=", "<=",
        ">=", "<", ">", "=", "(", ")", "{", "}", "[", "]", "::", ";", ":", ",", ".", ".."])

    private static let constants = Set<[UInt8]>(["true", "false", "nil", "..."])

    private var pending: [UInt8] = ""
    internal var line: Int = 1
    internal var col: Int = 1
    private var current: Token? = nil
    internal let name: [UInt8]
    private let reader: () async throws -> [UInt8]?
    private var final = false

    private mutating func tokenize(_ text: [UInt8]) throws {
        let text = pending + text
        var start = 0
        pending = ""
        current = nil
        while start < text.count {
            let oldstart = start
            var found = false
            for v in LuaLexer.classes_precedence {
                let m = try StringMatch.match(in: text, for: LuaLexer.classes[v]!, from: start)
                if !m.isEmpty {
                    guard case let .string(ss) = m[0] else {
                        assert(false)
                        throw Lua.LuaError.internalError
                    }
                    var s = ss.bytes
                    var e: Double = 0
                    if case let .number(e_) = m[1] {e = e_}
                    if v == "dquote" || v == "squote" {
                        var ok = true
                        while (try StringMatch.match(in: (try StringMatch.gsub(in: s, replace: "\\.", with: "")).0, for: LuaLexer.classes[v]!)).isEmpty {
                            let m2 = try StringMatch.match(in: text, for: LuaLexer.classes[v]!, from: Int(e) - 2)
                            if m2.isEmpty {
                                ok = false
                                break
                            }
                            guard case let .string(ss2) = m2[0] else {
                                assert(false)
                                throw Lua.LuaError.internalError
                            }
                            guard case let .number(e2) = m2[1] else {
                                assert(false)
                                throw Lua.LuaError.internalError
                            }
                            let s2 = ss2.bytes
                            s += s2[s2.index(after: s2.startIndex)...]
                            e = e2
                        }
                        if !ok {break}
                    } else if v == "operator" && s.count > 1 {
                        while !(LuaLexer.operators.contains(s) || s == "...") && s.count > 1 {
                            s = [UInt8](s[..<s.index(before: s.endIndex)])
                            e -= 1
                        }
                    }
                    if m.count > 2 {
                        guard case let .number(e2) = m[2] else {
                            assert(false)
                            throw Lua.LuaError.internalError
                        }
                        e = e2
                    }
                    found = true
                    switch v {
                        case "operator", "eq1", "eq2", "dot", "minus", "self", "label", "concat", "vararg":
                            if s == "..." {
                                current = .constant(.vararg, line: line)
                            } else if let op = Operator(rawValue: s.string) {
                                current = .operator(op, line: line)
                            } else {
                                throw Lua.LuaError.runtimeError(message: "\(name):\(line): invalid operator")
                            }
                        case "name":
                            if LuaLexer.keywords.contains(s) {
                                current = .keyword(Keyword(rawValue: s.string)!, line: line)
                            } else if LuaLexer.constants.contains(s) {
                                current = .constant(Constant(rawValue: s.string)!, line: line)
                            } else if LuaLexer.operators.contains(s) {
                                current = .operator(Operator(rawValue: s.string)!, line: line)
                            } else {
                                current = .name(s.string, line: line)
                            }
                        case "number", "decnumber", "scinumber", "decscinumber", "hexnumber", "dechexnumber", "scihexnumber", "decscihexnumber":
                            if let n = Double(s.string) {
                                current = .number(n, line: line)
                            } else {
                                throw Lua.LuaError.runtimeError(message: "\(name):\(line): invalid number")
                            }
                        case "linecomment", "blockcomment", "emptyblockcomment", "whitespace", "invalid":
                            found = false
                        case "blockquote", "emptyblockquote":
                            var sub = s[s.index(after: s.startIndex)..<s.index(before: s.endIndex)]
                            while s.first == "=" {
                                sub = sub[sub.index(after: sub.startIndex)..<sub.index(before: sub.endIndex)]
                            }
                            sub = sub[sub.index(after: sub.startIndex)..<sub.index(before: sub.endIndex)]
                            current = .string([UInt8](sub), line: line)
                        case "squote", "dquote":
                            let str = [UInt8](s[s.index(after: s.startIndex)..<s.index(before: s.endIndex)])
                            var parsed = [UInt8]()
                            var i = str.startIndex
                            while i < str.endIndex {
                                let c = str[i]
                                i = str.index(after: i)
                                if c == "\\" {
                                    if i == str.endIndex {
                                        throw Lua.LuaError.runtimeError(message: "\(name):\(line): unfinished escape sequence")
                                    }
                                    switch str[i] {
                                        case "a": parsed.append("\u{07}")
                                        case "b": parsed.append("\u{08}")
                                        case "f": parsed.append("\u{0C}")
                                        case "n": parsed.append("\n")
                                        case "r": parsed.append("\r")
                                        case "t": parsed.append("\t")
                                        case "v": parsed.append("\u{0B}")
                                        case "x":
                                            i = str.index(after: i)
                                            if i == str.endIndex {
                                                throw Lua.LuaError.runtimeError(message: "\(name):\(line): unfinished escape sequence")
                                            }
                                            var num = [str[i]]
                                            i = str.index(after: i)
                                            if i == str.endIndex {
                                                throw Lua.LuaError.runtimeError(message: "\(name):\(line): unfinished escape sequence")
                                            }
                                            num.append(str[i])
                                            guard let n = UInt8(num.string, radix: 16) else {
                                                throw Lua.LuaError.runtimeError(message: "\(name):\(line): malformed escape sequence")
                                            }
                                            parsed.append(n)
                                        case "u":
                                            i = str.index(after: i)
                                            if i == str.endIndex {
                                                throw Lua.LuaError.runtimeError(message: "\(name):\(line): unfinished escape sequence")
                                            }
                                            if str[i] != "{" {
                                                throw Lua.LuaError.runtimeError(message: "\(name):\(line): invalid escape sequence")
                                            }
                                            i = str.index(after: i)
                                            if i == str.endIndex {
                                                throw Lua.LuaError.runtimeError(message: "\(name):\(line): unfinished escape sequence")
                                            }
                                            var num = [str[i]]
                                            i = str.index(after: i)
                                            while i != str.endIndex && isxdigit(Int32(str[i])) != 0 {
                                                num.append(str[i])
                                                i = str.index(after: i)
                                            }
                                            if i == str.endIndex || str[i] != "{" {
                                                throw Lua.LuaError.runtimeError(message: "\(name):\(line): invalid escape sequence")
                                            }
                                            guard let n = UInt8(num.string, radix: 16) else {
                                                throw Lua.LuaError.runtimeError(message: "\(name):\(line): malformed escape sequence")
                                            }
                                            parsed.append(n)
                                        case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
                                            var num = [str[i]]
                                            i = str.index(after: i)
                                            while i != str.endIndex && isdigit(Int32(str[i])) != 0 && num.count < 3 {
                                                num.append(str[i])
                                                i = str.index(after: i)
                                            }
                                            i = str.index(before: i)
                                            guard let n = UInt8(num.string) else {
                                                throw Lua.LuaError.runtimeError(message: "\(name):\(line): malformed escape sequence")
                                            }
                                            parsed.append(n)
                                        default: parsed.append(str[i])
                                    }
                                    i = str.index(after: i)
                                } else {
                                    parsed.append(c)
                                }
                            }
                            current = .string(parsed, line: line)
                        default: assert(false); throw Lua.LuaError.internalError
                    }
                    start = Int(e) - 1
                    let nl = s.count(of: "\n")
                    if nl == 0 {
                        col += s.count
                    } else {
                        line += nl
                        //col = s.firstMatch(of: try! Regex("[^\n]*$"))?.count ?? 0
                    }
                    break
                }
            }
            if found || start == oldstart {
                pending = [UInt8](text[text.index(text.startIndex, offsetBy: start)...])
                break
            }
        }
    }

    internal init(using reader: @escaping () async throws -> [UInt8]?, named: [UInt8] = "") {
        self.reader = reader
        self.name = named
    }

    internal init(from str: [UInt8], named: [UInt8] = "") {
        var called = false
        self.init(using: {if !called {called = true; return str} else {return nil}}, named: named)
    }

    internal mutating func next() async throws -> Token? {
        if final {
            try tokenize("")
            //print(self.current)
            return self.current
        }
        try tokenize("")
        while self.current == nil {
            if let data = try await reader() {
                //print(data, pending)
                try tokenize(data)
            } else {
                final = true
                //print("final", pending)
                try tokenize(" ")
                //print(self.current)
                return self.current
            }
        }
        //print(self.current)
        return self.current
    }
}
