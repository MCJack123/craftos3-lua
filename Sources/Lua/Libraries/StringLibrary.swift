internal struct StringLibrary: LuaLibrary {
    public let name = "string"

    private static func index(string str: String, at index: Int) -> String.Index {
        if index >= 1 {return str.index(str.startIndex, offsetBy: index - 1)}
        else if index < 0 {return str.index(str.startIndex, offsetBy: str.count - index)}
        else {return str.startIndex}
    }

    public let byte = LuaSwiftFunction {state, args in
        let str = try args.checkString(at: 1)
        let _start = try args.checkInt(at: 2, default: 1)
        let start = index(string: str, at: _start)
        let end = index(string: str, at: try args.checkInt(at: 3, default: _start))
        return str.unicodeScalars[start...end].map {LuaValue.number(Double($0.value))}
    }

    public let char = LuaSwiftFunction {state, args in
        return [.string(.string(String(try args.args.map {Character(Unicode.Scalar(UInt32(try $0.checkNumber(at: 0)))!)})))]
    }

    public let dump = LuaSwiftFunction {state, args in
        let function = try args.checkFunction(at: 1)
        switch function {
            case .swift: return []
            case .lua(let fn):
                let dump = fn.proto.dump()
                return [.string(.string(String(dump.map {Character(Unicode.Scalar(UInt32($0))!)})))]
        }
    }

    public let find = LuaSwiftFunction {state, args in
        let str = try args.checkString(at: 1)
        let pat = try args.checkString(at: 2)
        let idx = try args.checkInt(at: 3, default: 1)
        if args[4].toBool || !pat.contains(try! Regex("[\\^\\$\\*\\+\\?\\.\\(\\[%\\-]")) {
            if let range = str.firstRange(of: pat) {
                return [
                    .number(Double(str.distance(from: str.startIndex, to: range.lowerBound) + 1)),
                    .number(Double(str.distance(from: str.startIndex, to: range.upperBound) + 1)),
                ]
            } else {
                return []
            }
        }
        if let res = try StringMatch.find(in: str, for: pat, from: idx - 1) {
            var v = res.2
            v.insert(.number(Double(res.1 + 1)), at: 0)
            v.insert(.number(Double(res.0 + 1)), at: 0)
            return v
        } else {
            return []
        }
    }



    public let gmatch = LuaSwiftFunction {state, args in
        var ms = StringMatch.gmatch(in: try args.checkString(at: 1), for: try args.checkString(at: 2))
        return [.function(.swift(LuaSwiftFunction {_, _ in
            return try ms.next()
        }))]
    }

    public let gsub = LuaSwiftFunction {state, args in
        let max = args[4] == .nil ? nil : try args.checkInt(at: 4)
        let res = try await StringMatch.gsub(in: args.checkString(at: 1), replace: args.checkString(at: 2), with: args[3], max: max, thread: state.thread)
        return [.string(.string(res.0)), .number(Double(res.1))]
    }

    public let len = LuaSwiftFunction {state, args in
        return [.number(Double(try args.checkString(at: 1).count))]
    }

    public let lower = LuaSwiftFunction {state, args in
        return [.string(.string(try args.checkString(at: 1).lowercased()))]
    }

    public let match = LuaSwiftFunction {state, args in
        let str = try args.checkString(at: 1)
        let pat = try args.checkString(at: 2)
        let idx = try args.checkInt(at: 3, default: 1)
        return try StringMatch.match(in: str, for: pat, from: idx)
    }

    public let rep = LuaSwiftFunction {state, args in
        if let sep = try? args.checkString(at: 2) {
            let s = String(repeating: try args.checkString(at: 1) + sep, count: try args.checkInt(at: 2))
            return [.string(.substring(s[s.startIndex ..< s.index(s.endIndex, offsetBy: -sep.count)]))]
        } else {
            return [.string(.string(String(repeating: try args.checkString(at: 1), count: try args.checkInt(at: 2))))]
        }
    }

    public let reverse = LuaSwiftFunction {state, args in
        return [.string(.string(String(try args.checkString(at: 1).reversed())))]
    }

    public let sub = LuaSwiftFunction {state, args in
        let s = try args.checkString(at: 1)
        let i = index(string: s, at: try args.checkInt(at: 2) - 1)
        let j = index(string: s, at: try args.checkInt(at: 3, default: -1) - 1)
        return [.string(.substring(s[i...j]))]
    }

    public let upper = LuaSwiftFunction {state, args in
        return [.string(.string(try args.checkString(at: 1).uppercased()))]
    }
}