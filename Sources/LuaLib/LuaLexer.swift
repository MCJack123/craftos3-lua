import Lua

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
        case string(String, line: Int)
        case number(Double, line: Int)

        internal var text: String {
            switch self {
                case .keyword(let kw, _): return kw.rawValue
                case .constant(let k, _): return k.rawValue
                case .operator(let op, _): return op.rawValue
                case .name(let str, _): return str
                case .string(let str, _): return str
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

    private static let classes = [
        "operator": "^([;:=%.,%[%]%(%)%{%}%+%-%*/%^%%<>~#&|][=%.%:]?%.?)()",
        "name": "^([%a_][%w_]*)()",
        "number": "^(%d+%.?%d*)()",
        "decnumber": "^(%.?%d+)()",
        "scinumber": "^(%d+%.?%d*[eE][%+%-]?%d+)()",
        "decscinumber": "^(%.?%d+[eE][%+%-]?%d+)()",
        "hexnumber": "^(0[xX]%x+%.?%x*)()",
        "dechexnumber": "^(0[xX]%.?%x+)()",
        "scihexnumber": "^(0[xX]%.?%x+[pP][%+%-]?%x+)()",
        "decscihexnumber": "^(0[xX]%x+%.?%x*[pP][%+%-]?%x+)()",
        "linecomment": "^(%-%-[^\n]*)()",
        "blockcomment": "^(%-%-%[(=*)%[.-%]%2%])()",
        "emptyblockcomment": "^(%-%-%[(=*)%[%]%2%])()",
        "blockquote": "^(%[(=*)%[.-%]%2%])()",
        "emptyblockquote": "^(%[(=*)%[%]%2%])()",
        "dquote": "^(\"[^\"]*\")()",
        "squote": "^('[^']*')()",
        "whitespace": "^(%s+)()",
        "invalid": "^([^%w%s_;:=%.,%[%]%(%)%{%}%+%-%*/%^%%<>~#&|]+)()",
    ]

    private static let classes_precedence = [
        "name", "scihexnumber", "decscihexnumber", "hexnumber", "dechexnumber",
        "scinumber", "decscinumber", "number", "decnumber",
        "blockcomment", "emptyblockcomment", "linecomment", "blockquote",
        "emptyblockquote", "operator", "dquote", "squote", "whitespace", "invalid"]
    
    private static let keywords = Set([
        "break", "do", "else", "elseif", "end", "for", "function", "goto", "if",
        "in", "local", "repeat", "return", "then", "until", "while"])
    
    private static let operators = Set([
        "and", "not", "or", "+", "-", "*", "/", "%", "^", "#", "==", "~=", "<=",
        ">=", "<", ">", "=", "(", ")", "{", "}", "[", "]", "::", ";", ":", ",", ".", ".."])

    private static let constants = Set(["true", "false", "nil", "..."])

    private var pending: String = ""
    internal var line: Int = 1
    internal var col: Int = 1
    private var current: Token? = nil
    internal let name: String
    private let reader: () async throws -> String?

    private mutating func tokenize(_ text: String) throws {
        let text = pending + text
        var start = 0
        pending = ""
        current = nil
        while start < text.count {
            var found = false
            for v in LuaLexer.classes_precedence {
                let m = try StringMatch.match(in: text, for: LuaLexer.classes[v]!, from: start)
                if !m.isEmpty {
                    guard case let .string(ss) = m[0] else {
                        assert(false)
                        throw Lua.LuaError.internalError
                    }
                    var s = ss.string
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
                            let s2 = ss2.string
                            s += s2[s2.index(after: s2.startIndex)...]
                            e = e2
                        }
                        if !ok {break}
                    } else if v == "operator" && s.count > 1 {
                        while !(LuaLexer.operators.contains(s) || s == "...") && s.count > 1 {
                            s = String(s[..<s.index(before: s.endIndex)])
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
                        case "operator":
                            if s == "..." {
                                current = .constant(.vararg, line: line)
                            } else if let op = Operator(rawValue: s) {
                                current = .operator(op, line: line)
                            } else {
                                throw Lua.LuaError.runtimeError(message: "\(name):\(line): invalid operator")
                            }
                        case "name":
                            if LuaLexer.keywords.contains(s) {
                                current = .keyword(Keyword(rawValue: s)!, line: line)
                            } else if LuaLexer.constants.contains(s) {
                                current = .constant(Constant(rawValue: s)!, line: line)
                            } else if LuaLexer.operators.contains(s) {
                                current = .operator(Operator(rawValue: s)!, line: line)
                            } else {
                                current = .name(s, line: line)
                            }
                        case "number", "decnumber", "scinumber", "decscinumber", "hexnumber", "dechexnumber", "scihexnumber", "decscihexnumber":
                            if let n = Double(s) {
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
                            current = .string(String(sub), line: line)
                        case "squote", "dquote":
                            current = .string(String(s[s.index(after: s.startIndex)..<s.index(before: s.endIndex)]), line: line)
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
            if found {
                pending = String(text[text.index(text.startIndex, offsetBy: start)...])
                break
            }
        }
    }

    internal init(using reader: @escaping () async throws -> String?, named: String = "") {
        self.reader = reader
        self.name = named
    }

    internal init(from str: String, named: String = "") {
        var called = false
        self.init(using: {if !called {called = true; return str} else {return nil}}, named: named)
    }

    internal mutating func next() async throws -> Token? {
        try tokenize("")
        if let current = current {
            //print(current)
            return current
        }
        if let data = try await reader() {
            try tokenize(data)
            return self.current
        } else {
            return nil
        }
    }
}
