public enum LuaValue: Hashable {
    case `nil`
    case boolean(Bool)
    case number(Double)
    case string(LuaString)
    case function(LuaFunction)
    case userdata(LuaUserdata)
    case thread(LuaThread)
    case table(LuaTable)

    internal struct Constants {
        internal static let `true` = LuaValue.boolean(true)
        internal static let `false` = LuaValue.boolean(false)
        internal static let zero = LuaValue.number(0)
        internal static let one = LuaValue.number(1)
        internal static let __index = LuaValue.string(.string("__index"))
        internal static let __newindex = LuaValue.string(.string("__newindex"))
        internal static let __call = LuaValue.string(.string("__call"))
        internal static let __unm = LuaValue.string(.string("__unm"))
        internal static let __len = LuaValue.string(.string("__len"))
        internal static let __concat = LuaValue.string(.string("__concat"))
        internal static let __eq = LuaValue.string(.string("__eq"))
        internal static let __lt = LuaValue.string(.string("__lt"))
        internal static let __le = LuaValue.string(.string("__le"))
        internal static let __gc = LuaValue.string(.string("__gc"))
        internal static let __mode = LuaValue.string(.string("__mode"))
        internal static let arithops: [LuaOpcode.Operation: LuaValue] = [
            .ADD: .string(.string("__add")),
            .SUB: .string(.string("__sub")),
            .MUL: .string(.string("__mul")),
            .DIV: .string(.string("__div")),
            .MOD: .string(.string("__mod")),
            .POW: .string(.string("__pow"))
        ]
    }

    public func metatable(in state: LuaState) -> LuaTable? {
        switch self {
            case .table(let tbl): return tbl.metatable
            case .userdata(let ud): return ud.metatable
            case .nil: return state.nilMetatable
            case .boolean: return state.booleanMetatable
            case .number: return state.numberMetatable
            case .string: return state.stringMetatable
            case .function: return state.functionMetatable
            case .thread: return state.threadMetatable
        }
    }

    public var type: String {
        switch self {
            case .nil: return "nil"
            case .boolean: return "boolean"
            case .number: return "number"
            case .string: return "string"
            case .function: return "function"
            case .userdata: return "userdata"
            case .thread: return "thread"
            case .table: return "table"
        }
    }

    public var toString: String {
        switch self {
            case .nil: return "nil"
            case .boolean(let val): return val ? "true" : "false"
            case .number(let val): return String(val)
            case .string(let val): return val.string
            case .function(let val):
                switch val {
                    case .lua(let cl): return "function: \(String(UInt(bitPattern: Unmanaged.passUnretained(cl).toOpaque()), radix: 16))"
                    case .swift(let cl): return "function: \(String(UInt(bitPattern: Unmanaged.passUnretained(cl).toOpaque()), radix: 16))"
                }
            case .userdata(let val): return "userdata: \(String(UInt(bitPattern: Unmanaged.passUnretained(val).toOpaque()), radix: 16))"
            case .thread(let val): return "thread: \(String(UInt(bitPattern: Unmanaged.passUnretained(val).toOpaque()), radix: 16))"
            case .table(let val): return "table: \(String(UInt(bitPattern: Unmanaged.passUnretained(val).toOpaque()), radix: 16))"
        }
    }

    public var toBool: Bool {
        return self != .nil && self != .boolean(false)
    }

    public var toNumber: Double? {
        switch self {
            case .number(let val): return val
            case .string(let val): return Double(val.string)
            default: return nil
        }
    }

    public func checkBoolean(at index: Int, default defaultValue: Bool? = nil) throws -> Bool {
        if defaultValue != nil && self == .nil {
            return defaultValue!
        }
        if case let .boolean(val) = self {
            return val
        }
        throw Lua.argumentError(at: index, for: self, expected: "boolean")
    }

    public func checkNumber(at index: Int, default defaultValue: Double? = nil) throws -> Double {
        if defaultValue != nil && self == .nil {
            return defaultValue!
        }
        if case let .number(val) = self {
            return val
        }
        throw Lua.argumentError(at: index, for: self, expected: "number")
    }

    public func checkInt(at index: Int, default defaultValue: Int? = nil) throws -> Int {
        if defaultValue != nil && self == .nil {
            return defaultValue!
        }
        if case let .number(val) = self {
            return Int(val)
        }
        throw Lua.argumentError(at: index, for: self, expected: "number")
    }

    public func checkString(at index: Int, default defaultValue: String? = nil) throws -> String {
        if defaultValue != nil && self == .nil {
            return defaultValue!
        }
        if case let .string(val) = self {
            return val.string
        }
        throw Lua.argumentError(at: index, for: self, expected: "string")
    }

    public func checkTable(at index: Int, default defaultValue: LuaTable? = nil) throws -> LuaTable {
        if defaultValue != nil && self == .nil {
            return defaultValue!
        }
        if case let .table(val) = self {
            return val
        }
        throw Lua.argumentError(at: index, for: self, expected: "table")
    }

    public func checkFunction(at index: Int, default defaultValue: LuaFunction? = nil) throws -> LuaFunction {
        if defaultValue != nil && self == .nil {
            return defaultValue!
        }
        if case let .function(val) = self {
            return val
        }
        throw Lua.argumentError(at: index, for: self, expected: "function")
    }

    public func checkThread(at index: Int, default defaultValue: LuaThread? = nil) throws -> LuaThread {
        if defaultValue != nil && self == .nil {
            return defaultValue!
        }
        if case let .thread(val) = self {
            return val
        }
        throw Lua.argumentError(at: index, for: self, expected: "thread")
    }

    public func checkUserdata(at index: Int, default defaultValue: LuaUserdata? = nil) throws -> LuaUserdata {
        if defaultValue != nil && self == .nil {
            return defaultValue!
        }
        if case let .userdata(val) = self {
            return val
        }
        throw Lua.argumentError(at: index, for: self, expected: "userdata")
    }

    public func checkUserdata<T>(at index: Int, with type: T.Type, default defaultValue: T? = nil) throws -> T {
        if defaultValue != nil && self == .nil {
            return defaultValue!
        }
        if case let .userdata(val) = self, let v = val.object as? T {
            return v
        }
        throw Lua.argumentError(at: index, for: self, expected: String(reflecting: T.self))
    }

    public func orElse(_ val: LuaValue) -> LuaValue {
        if self == .nil {
            return val
        } else {
            return self
        }
    }
}