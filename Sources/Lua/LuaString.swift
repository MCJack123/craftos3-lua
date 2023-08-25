public enum LuaString: Hashable, Comparable {
    case string(String)
    case substring(Substring)
    indirect case rope(LuaString, LuaString)

    public var string: String {
        switch self {
            case .string(let val): return val
            case .substring(let val): return String(val)
            case .rope(let a, let b): return a.string + b.string
        }
    }

    public static func == (lhs: LuaString, rhs: LuaString) -> Bool {
        return lhs.string == rhs.string
    }

    public static func < (lhs: LuaString, rhs: LuaString) -> Bool {
        return lhs.string < rhs.string
    }

    public static func <= (lhs: LuaString, rhs: LuaString) -> Bool {
        return lhs.string <= rhs.string
    }
}