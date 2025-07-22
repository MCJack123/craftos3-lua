import Lua
import LibC

extension Collection where Element: Equatable {
    func firstRange_<C>(of other: C) -> Range<Self.Index>? where C : Collection, Self.Element == C.Element {
        if #available(macOS 13.0, iOS 16.0, tvOS 16.0, watchOS 9.0, *) {
            return firstRange(of: other)
        } else {
            var index = startIndex
            loop: while index != endIndex {
                var i2a = index
                var i2b = other.startIndex
                while i2b != other.endIndex {
                    if i2a == endIndex || self[i2a] != other[i2b] {
                        index = self.index(after: index)
                        continue loop
                    }
                    i2a = self.index(after: i2a)
                    i2b = other.index(after: i2b)
                }
                return index..<i2a
            }
            return nil
        }
    }
}

internal struct StringLibrary: LuaLibrary {
    public let name = "string"

    private static func index(string str: [UInt8], at index: Int, end: Bool) -> [UInt8].Index? {
        if index >= 1 {return str.index(str.startIndex, offsetBy: index - (end ? 0 : 1), limitedBy: end ? str.endIndex : str.index(before: str.endIndex)) ?? (end ? str.endIndex : nil)}
        else if index < 0 {
            if -index <= str.count {return str.index(str.startIndex, offsetBy: str.count + index + (end ? 1 : 0))}
            else {return str.startIndex}
        }
        else {return nil}
    }

    public let byte = LuaSwiftFunction {state, args in
        let str = try await args.checkBytes(at: 1)
        let _start = try await args.checkInt(at: 2, default: 1)
        guard let start = index(string: str, at: _start, end: false) else {return []}
        guard let end = index(string: str, at: try await args.checkInt(at: 3, default: _start), end: true) else {return []}
        return str[start..<end].map {LuaValue.number(Double($0))}
    }

    public let char = LuaSwiftFunction {state, args in
        return [.string(.string(String(try args.args.map {Character(Unicode.Scalar(UInt32(try $0.checkNumber(at: 0)))!)})))]
    }

    public let dump = LuaSwiftFunction {state, args in
        let function = try await args.checkFunction(at: 1)
        switch function {
            case .swift: throw await state.error("unable to dump given function")
            case .lua(let fn):
                let dump = await fn.proto.dump()
                return [.string(.string(dump))]
        }
    }
    
    private static let magicCharacters = Set<UInt8>((["^", "$", "*", "+", "-", "?", ".", "(", ")", "[", "]", "%"] as [Character]).map {$0.asciiValue!})

    public let find = LuaSwiftFunction {state, args in
        let str = try await args.checkBytes(at: 1)
        let pat = try await args.checkBytes(at: 2)
        guard let idx = index(string: str, at: try await args.checkInt(at: 3, default: 1), end: false) else {return []}
        if pat.isEmpty && idx == str.startIndex {
            return [.number(1), .number(1)]
        }
        if idx >= str.endIndex {return []}
        if args[4].toBool || !pat.contains(where: {StringLibrary.magicCharacters.contains($0)}) {
            if let range = str[idx...].firstRange_(of: pat) {
                return [
                    .number(Double(str.distance(from: str.startIndex, to: range.lowerBound) + 1)),
                    .number(Double(str.distance(from: str.startIndex, to: range.upperBound))),
                ]
            } else {
                return []
            }
        }
        if let res = try StringMatch.find(in: str, for: pat, from: idx) {
            var v = res.2
            v.insert(.number(Double(res.1 + 1)), at: 0)
            v.insert(.number(Double(res.0 + 1)), at: 0)
            return v
        } else {
            return []
        }
    }

    private actor Incrementor {
        private var num: Int
        public init(_ value: Int) {
            num = value
        }
        public func next() -> Int {
            let n = num
            num += 1
            return n
        }
    }

    public let format = LuaSwiftFunction {state, args in
        // TODO
        let format = try await args.checkBytes(at: 1)
        let index = Incrementor(2)
        let (str, n) = try await StringMatch.gsub(in: format, replace: "%%[sd]", with: .function(.swift(LuaSwiftFunction {_state, _args in
            let v = args[await index.next()]
            return [v]
        })), max: nil, thread: state.thread)
        return [.string(.string(str))]
    }

    private actor GmatchIsolator {
        private var ms: StringMatch.gmatch
        public init(_ value: StringMatch.gmatch) {
            ms = value
        }
        public func next() throws -> [LuaValue] {
            return try ms.next()
        }
    }

    public let gmatch = LuaSwiftFunction {state, args in
        let ms = GmatchIsolator(StringMatch.gmatch(in: try await args.checkBytes(at: 1), for: try await args.checkBytes(at: 2)))
        return [.function(.swift(LuaSwiftFunction {_, _ in
            return try await ms.next()
        }))]
    }

    public let gsub = LuaSwiftFunction {state, args in
        let max = args[4] == .nil ? nil : try await args.checkInt(at: 4)
        let res = try await StringMatch.gsub(in: args.checkBytes(at: 1), replace: args.checkBytes(at: 2), with: args[3], max: max, thread: state.thread)
        return [.string(.string(res.0)), .number(Double(res.1))]
    }

    public let len = LuaSwiftFunction {state, args in
        return [.number(Double(try await args.checkBytes(at: 1).count))]
    }

    public let lower = LuaSwiftFunction {state, args in
        return [.string(.string(try await args.checkBytes(at: 1).map {UInt8(tolower(CInt($0)))}))]
    }

    public let match = LuaSwiftFunction {state, args in
        let str = try await args.checkBytes(at: 1)
        let pat = try await args.checkBytes(at: 2)
        guard let idx = index(string: str, at: try await args.checkInt(at: 3, default: 1), end: false) else {
            throw await state.error("bad argument #3 (index out of range)")
        }
        return try StringMatch.match(in: str, for: pat, from: idx)
    }

    public let rep = LuaSwiftFunction {state, args in
        let val = try await args.checkBytes(at: 1)
        let count = try await args.checkInt(at: 2)
        let sep = try await args.checkBytes(at: 3, default: "")
        var retval = val
        if count <= 0 {
            return [.string(.string(""))]
        } else if count == 1 {
            return [.string(.string(val))]
        }
        for _ in 2...count {
            retval += sep + val
        }
        return [.string(.string(retval))]
    }

    public let reverse = LuaSwiftFunction {state, args in
        return [.string(.string([UInt8](try await args.checkBytes(at: 1).reversed())))]
    }

    public let sub = LuaSwiftFunction {state, args in
        let s = try await args.checkBytes(at: 1)
        guard let i = index(string: s, at: try await args.checkInt(at: 2), end: false) else {return [.string(.string(""))]}
        let j = index(string: s, at: try await args.checkInt(at: 3, default: -1), end: true) ?? s.endIndex
        if j < i {return [.string(.string(""))]}
        return [.string(.substring(s[i..<j]))]
    }

    public let upper = LuaSwiftFunction {state, args in
        return [.string(.string(try await args.checkBytes(at: 1).map {UInt8(toupper(CInt($0)))}))]
    }
}
