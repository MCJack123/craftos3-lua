import Lua

private struct StringPointer: Comparable {
    var string: [UInt8]
    var index: [UInt8].Index

    init(_ str: [UInt8]) {
        string = str
        index = string.startIndex
    }

    init(_ str: [UInt8], _ idx: [UInt8].Index) {
        string = str
        index = idx
    }

    var first: Character? {
        if index < string.startIndex || index >= string.endIndex {
            return nil
        }
        return Character(Unicode.Scalar(string[index]))
    }

    var firstByte: UInt8? {
        if index >= string.endIndex {
            return nil
        }
        return string[index]
    }

    func character(at n: Int) -> Character? {
        return Character(Unicode.Scalar(string[string.index(index, offsetBy: n)]))
    }

    func byte(at n: Int) -> UInt8? {
        return string[string.index(index, offsetBy: n)]
    }

    func advanced(by n: Int) -> StringPointer {
        var p = StringPointer(string)
        p.index = string.index(index, offsetBy: n)
        return p
    }

    mutating func advance(by n: Int) {
        index = string.index(index, offsetBy: n)
    }

    mutating func next() -> Character? {
        if index == string.endIndex {
            return nil
        }
        let c = Character(Unicode.Scalar(string[index]))
        index = string.index(after: index)
        return c
    }

    static func < (left: StringPointer, right: StringPointer) -> Bool {
        return left.index < right.index
    }

    static func + (left: StringPointer, right: Int) -> StringPointer {
        return left.advanced(by: right)
    }

    static func - (left: StringPointer, right: Int) -> StringPointer {
        return left.advanced(by: -right)
    }
}

internal class StringMatch {
    private var matchdepth: Int = 200
    private let src: [UInt8]
    private let src_end: StringPointer
    private let pattern: [UInt8]
    private let p_end: StringPointer
    private var captures = [(StringPointer, Int)]()

    private static let CAP_POSITION = -2
    private static let CAP_UNFINISHED = -1

    private init(_ str: [UInt8], _ p: [UInt8]) {
        src = str
        src_end = StringPointer(str, str.endIndex)
        pattern = p
        p_end = StringPointer(pattern, pattern.endIndex)
    }

    private func check_capture(_ l: Int) throws -> Int {
        if l < 1 || l > captures.count || captures[l-1].1 == StringMatch.CAP_UNFINISHED {
            throw Lua.LuaError.runtimeError(message: "invalid capture index %\(l)")
        }
        return l - 1
    }

    private func capture_to_close() throws -> Int {
        if let idx = captures.lastIndex(where: {$0.1 == StringMatch.CAP_UNFINISHED}) {
            return idx
        }
        throw Lua.LuaError.runtimeError(message: "invalid pattern capture")
    }

    private func classend(_ p: StringPointer) throws -> StringPointer {
        var p = p
        switch p.next() {
            case "%":
                if p == p_end {
                    throw Lua.LuaError.runtimeError(message: "malformed pattern string (ends with '%')")
                }
                return p + 1
            case "[":
                if p.first == "^" {_=p.next()}
                repeat {
                    if p == p_end {
                        throw Lua.LuaError.runtimeError(message: "malformed pattern string (missing ']')")
                    }
                    let cc = p.first
                    _=p.next()
                    if cc == "%" && p != p_end {
                        _=p.next()
                    }
                } while p.first != "]"
                return p + 1
            default:
                return p
        }
    }

    private static func match_class(_ c: Character, _ cl: Character) -> Bool {
        var res: Bool
        switch cl.lowercased() {
            case "a": res = c.isLetter
            case "c": res = (c.asciiValue ?? 0) < 0x20
            case "d": res = c.isNumber
            case "g": res = (c.asciiValue ?? 0) > 0x20 && (c.asciiValue ?? 0) < 0x7F
            case "l": res = c.isLowercase
            case "p": res = c.isPunctuation
            case "s": res = c.isWhitespace
            case "u": res = c.isUppercase
            case "w": res = c.isLetter || c.isNumber
            case "x": res = c.isHexDigit
            case "z": res = (c.asciiValue ?? 0) == 0
            default: return cl == c
        }
        return cl.isLowercase ? res : !res
    }

    private static func matchbracketclass(_ c: Character, _ p: StringPointer, _ ec: StringPointer) -> Bool {
        var sig = true
        var p = p
        if p.character(at: 1) == "^" {
            sig = false
            _=p.next()
        }
        _=p.next()
        while p < ec {
            if p.first == "%" {
                _=p.next()
                if match_class(c, p.first!) {
                    return sig
                }
            } else if p.character(at: 1) == "-" && p + 2 < ec {
                if p.character(at: 0)!.asciiValue! <= c.asciiValue! && c.asciiValue! <= p.character(at: 2)!.asciiValue! {
                    return sig
                }
                p.advance(by: 2)
            } else if p.first == c {
                return sig
            }
            _=p.next()
        }
        return !sig
    }

    private func singlematch(_ s: StringPointer, _ p: StringPointer, _ ep: StringPointer) -> Bool {
        if s >= src_end {
            return false
        } else if let c = s.first {
            switch p.first! {
                case ".": return true
                case "%": return StringMatch.match_class(c, p.character(at: 1)!)
                case "[": return StringMatch.matchbracketclass(c, p, ep - 1)
                default: return p.first == c
            }
        } else {
            return false
        }
    }

    private func matchbalance(_ s: StringPointer, _ p: StringPointer) throws -> StringPointer? {
        var s = s
        if p >= p_end - 1 {
            throw Lua.LuaError.runtimeError(message: "malformed pattern (missing arguments to '%b')")
        }
        if s.first != p.first {
            return nil
        } else {
            let b = p.first
            let e = p.character(at: 1)
            var cont = 1
            _=s.next()
            while s < src_end {
                if s.first == e {
                    cont -= 1
                    if cont == 0 {
                        return s + 1
                    }
                } else if s.first == b {
                    cont += 1
                }
            }
        }
        return nil
    }

    private func max_expand(_ s: StringPointer, _ p: StringPointer, _ ep: StringPointer) throws -> StringPointer? {
        var i = 0
        while singlematch(s + i, p, ep) {
            i += 1
        }
        while i >= 0 {
            if let res = try match(s + i, ep + 1) {
                return res
            }
            i -= 1
        }
        return nil
    }

    private func min_expand(_ s: StringPointer, _ p: StringPointer, _ ep: StringPointer) throws -> StringPointer? {
        var s = s
        while true {
            if let res = try match(s, ep + 1) {
                return res
            } else if singlematch(s, p, ep) {
                _=s.next()
            } else {
                return nil
            }
        }
    }

    private func start_capture(_ s: StringPointer, _ p: StringPointer, _ what: Int) throws -> StringPointer? {
        captures.append((s, what))
        let res = try match(s, p)
        if res == nil {
            captures.removeLast()
        }
        return res
    }

    private func end_capture(_ s: StringPointer, _ p: StringPointer) throws -> StringPointer? {
        let l = try capture_to_close()
        captures[l] = (captures[l].0, s.string.distance(from: captures[l].0.index, to: s.index))
        let res = try match(s, p)
        if res == nil {
            captures[l] = (captures[l].0, StringMatch.CAP_UNFINISHED)
        }
        return res
    }

    private func match_capture(_ s: StringPointer, _ l: Int) throws -> StringPointer? {
        let l = try check_capture(l)
        let len = captures[l].1
        if s.string.distance(from: s.index, to: src_end.index) >= len &&
            s.string[captures[l].0.index ..< s.string.index(captures[l].0.index, offsetBy: len)] == s.string[s.index ..< s.string.index(s.index, offsetBy: len)] {
            return s + len
        } else {
            return nil
        }
    }

    private func match_default(_ s: inout StringPointer?, _ p: inout StringPointer) throws -> Bool {
        let ep = try classend(p)
        if !singlematch(s!, p, ep) {
            if ep.first == "*" || ep.first == "?" || ep.first == "-" {
                p = ep + 1
                return true
            } else {
                s = nil
            }
        } else {
            switch ep.first {
                case "?":
                    if let res = try match(s! + 1, ep + 1) {
                        s = res
                    } else {
                        p = ep + 1
                        return true
                    }
                case "+":
                    _=s!.next()
                    fallthrough
                case "*":
                    s = try max_expand(s!, p, ep)
                case "-":
                    s = try min_expand(s!, p, ep)
                default:
                    _=s!.next()
                    p = ep
                    return true
            }
        }
        return false
    }

    private func match(_ s: StringPointer, _ p: StringPointer) throws -> StringPointer? {
        var s: StringPointer? = s
        var p = p
        if matchdepth == 0 {
            throw Lua.LuaError.runtimeError(message: "pattern too complex")
        }
        matchdepth -= 1
        _init: while true {
            if p != p_end {
                switch p.first {
                    case "(":
                        if p.character(at: 1) == ")" {
                            s = try start_capture(s!, p + 2, StringMatch.CAP_POSITION)
                        } else {
                            s = try start_capture(s!, p + 1, StringMatch.CAP_UNFINISHED)
                        }
                    case ")":
                        s = try end_capture(s!, p + 1)
                    case "$":
                        if p + 1 != p_end {
                            if try match_default(&s, &p) {
                                continue _init
                            }
                        }
                        s = s == src_end ? s : nil
                    case "%":
                        switch p.character(at: 1) {
                            case "b":
                                s = try matchbalance(s!, p + 2)
                                if s != nil {
                                    p = p + 4
                                    continue _init
                                }
                            case "f":
                                p = p + 2
                                if p.first != "[" {
                                    throw Lua.LuaError.runtimeError(message: "missing '[' after '%f' in pattern")
                                }
                                let ep = try classend(p)
                                let previous = s!.index == src.startIndex ? "\0" : s!.character(at: -1)!
                                if !StringMatch.matchbracketclass(previous, p, ep - 1) && StringMatch.matchbracketclass(s!.first!, p, ep - 1) {
                                    p = ep
                                    continue _init
                                }
                                s = nil
                            case "0", "1", "2", "3", "4", "5", "6", "7", "8", "9":
                                s = try match_capture(s!, p.character(at: 1)!.wholeNumberValue!)
                                if s != nil {
                                    p = p + 2
                                    continue _init
                                }
                            default:
                                if try match_default(&s, &p) {
                                    continue _init
                                }
                        }
                    default:
                        if try match_default(&s, &p) {
                            continue _init
                        }
                }
            }
            break
        }
        matchdepth += 1
        return s
    }

    private func push_onecapture(_ i: Int, _ s: StringPointer?, _ e: StringPointer?) throws -> LuaValue {
        if i >= captures.count {
            if i == 0, let s = s, let e = e {
                return .string(.substring(s.string[s.index..<e.index]))
            } else {
                throw Lua.LuaError.runtimeError(message: "invalid capture index")
            }
        } else {
            let l = captures[i].1
            if l == StringMatch.CAP_UNFINISHED {
                throw Lua.LuaError.runtimeError(message: "unfinished capture")
            } else if l == StringMatch.CAP_POSITION {
                return .number(Double(captures[i].0.string.distance(from: src.startIndex, to: captures[i].0.index) + 1))
            } else {
                let c = captures[i].0
                return .string(.substring(c.string[c.index ..< c.string.index(c.index, offsetBy: captures[i].1)]))
            }
        }
    }

    private func push_captures(_ s: StringPointer?, _ e: StringPointer?) throws -> [LuaValue] {
        let nlevels = captures.count == 0 && s != nil ? 1 : captures.count
        var retval = [LuaValue](repeating: .nil, count: nlevels)
        for i in 0..<nlevels {
            retval[i] = try push_onecapture(i, s, e)
        }
        return retval
    }

    internal static func find(in str: [UInt8], for p: [UInt8], from index: Int = 0) throws -> (Int, Int, [LuaValue])? {
        var p = p
        let anchor = p.first == ("^" as Character).asciiValue
        if anchor {
            p = [UInt8](p[p.index(after: p.startIndex)...])
        }
        let ms = StringMatch(str, p)
        var s1 = StringPointer(str, str.index(str.startIndex, offsetBy: index))
        let pp = StringPointer(p)
        repeat {
            if let res = try ms.match(s1, pp) {
                return (str.distance(from: str.startIndex, to: s1.index), str.distance(from: str.startIndex, to: res.index), try ms.push_captures(nil, nil))
            }
            _=s1.next()
        } while s1 < ms.src_end && !anchor
        return nil
    }

    internal static func match(in str: [UInt8], for p: [UInt8], from index: Int = 0) throws -> [LuaValue] {
        var p = p
        let anchor = p.first == ("^" as Character).asciiValue
        if anchor {
            p = [UInt8](p[p.index(after: p.startIndex)...])
        }
        let ms = StringMatch(str, p)
        var s1 = StringPointer(str, str.index(str.startIndex, offsetBy: index))
        let pp = StringPointer(p)
        repeat {
            if let res = try ms.match(s1, pp) {
                return try ms.push_captures(s1, res)
            }
            _=s1.next()
        } while s1 < ms.src_end && !anchor
        return []
    }

    internal struct gmatch {
        private let s: [UInt8]
        private let p: [UInt8]
        private var src: StringPointer

        internal init(in str: [UInt8], for pat: [UInt8]) {
            s = str
            p = pat
            src = StringPointer(str)
        }

        internal mutating func next() throws -> [LuaValue] {
            let ms = StringMatch(s, p)
            let pp = StringPointer(p)
            while src < ms.src_end {
                ms.captures = []
                if let e = try ms.match(src, pp) {
                    src = e
                    if e == src {
                        _=src.next()
                    }
                    return try ms.push_captures(src, e)
                }
                _=src.next()
            }
            return []
        }
    }

    internal static func gsub(in str: [UInt8], replace p: [UInt8], with rep: LuaValue, max: Int? = nil, thread: LuaThread? = nil) async throws -> ([UInt8], Int) {
        var p = p
        let anchor = p.first == ("^" as Character).asciiValue
        if anchor {
            p = [UInt8](p[p.index(after: p.startIndex)...])
        }
        let ms = StringMatch(str, p)
        var src = StringPointer(str)
        let pp = StringPointer(p)
        var n = 0
        var retval = [UInt8]()
        while max == nil || n < max! {
            ms.captures = []
            let e = try ms.match(src, pp)
            if let e = e {
                n += 1
                let res: LuaValue
                switch rep {
                    case .function(let f):
                        guard let thread = thread else {
                            throw Lua.LuaError.runtimeError(message: "internal error: gsub called with function argument, but no thread provided")
                        }
                        res = (try await f.call(in: thread, with: ms.push_captures(src, e))).first ?? .nil
                    case .table(let t):
                        res = await t[try ms.push_onecapture(0, src, e)]
                    default:
                        let rstr = await rep.toBytes
                        var resstr = [UInt8]()
                        var i = StringPointer(rstr)
                        while i.index < rstr.endIndex {
                            if i.first != "%" {
                                resstr.append(i.firstByte!)
                            } else {
                                _=i.next()
                                if let c = i.first {
                                    if !c.isNumber {
                                        resstr.append(i.firstByte!)
                                    } else if c == "0" {
                                        resstr.append(contentsOf: str[src.index..<e.index])
                                    } else {
                                        resstr.append(contentsOf: try await ms.push_onecapture(c.wholeNumberValue! - 1, src, e).toBytes)
                                    }
                                } else {
                                    throw Lua.LuaError.runtimeError(message: "incomplete replacement string")
                                }
                            }
                            _=i.next()
                        }
                        res = .string(.string(resstr))
                }
                if res == .nil || res == .boolean(false) {
                    retval.append(contentsOf: str[src.index..<e.index])
                } else {
                    retval.append(contentsOf: await res.toBytes)
                }
            }
            if let e = e, e > src {
                src = e
            } else if src < ms.src_end {
                retval.append(UInt8(src.next()!.unicodeScalars.first!.value))
            } else {
                break
            }
            if anchor {
                break
            }
        }
        retval.append(contentsOf: str[src.index...])
        return (retval, n)
    }

    internal static func gsub(in str: [UInt8], replace p: [UInt8], with rstr: [UInt8], max: Int? = nil) async throws -> ([UInt8], Int) {
        var p = p
        let anchor = p.first == ("^" as Character).asciiValue!
        if anchor {
            p = [UInt8](p[p.index(after: p.startIndex)...])
        }
        let ms = StringMatch(str, p)
        var src = StringPointer(str)
        let pp = StringPointer(p)
        var n = 0
        var retval = [UInt8]()
        while max == nil || n < max! {
            ms.captures = []
            let e = try ms.match(src, pp)
            if let e = e {
                n += 1
                var resstr = [UInt8]()
                var i = StringPointer(rstr)
                while i.index < rstr.endIndex {
                    if i.first != "%" {
                        resstr.append(i.firstByte!)
                    } else {
                        _=i.next()
                        if let c = i.first {
                            if !c.isNumber {
                                resstr.append(i.firstByte!)
                            } else if c == "0" {
                                resstr.append(contentsOf: str[src.index..<e.index])
                            } else {
                                resstr.append(contentsOf: try await ms.push_onecapture(c.wholeNumberValue! - 1, src, e).toBytes)
                            }
                        } else {
                            throw Lua.LuaError.runtimeError(message: "incomplete replacement string")
                        }
                    }
                    _=i.next()
                }
                retval.append(contentsOf: resstr)
            }
            if let e = e, e > src {
                src = e
            } else if src < ms.src_end {
                retval.append(UInt8(src.next()!.unicodeScalars.first!.value))
            } else {
                break
            }
            if anchor {
                break
            }
        }
        retval.append(contentsOf: str[src.index...])
        return (retval, n)
    }
}
