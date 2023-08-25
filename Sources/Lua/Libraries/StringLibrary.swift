internal struct StringLibrary: LuaLibrary {
    public let name = "string"

    private static func index(string str: String, at index: Int) -> String.Index {
        if index >= 1 {return str.index(str.startIndex, offsetBy: index - 1)}
        else if index < 0 {return str.index(str.startIndex, offsetBy: str.count - index)}
        else {return str.startIndex}
    }

    public let byte = LuaSwiftFunction {state, args in
        let str = try args[0].checkString(at: 1)
        let _start = try args[1].checkInt(at: 2, default: 1)
        let start = index(string: str, at: _start)
        let end = index(string: str, at: try args[2].checkInt(at: 3, default: _start))
        return str.unicodeScalars[start...end].map {LuaValue.number(Double($0.value))}
    }

    public let char = LuaSwiftFunction {state, args in
        return [.string(.string(String(try args.map {Character(Unicode.Scalar(UInt32(try $0.checkNumber(at: 0)))!)})))]
    }
}