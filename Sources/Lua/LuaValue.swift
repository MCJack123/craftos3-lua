public enum LuaValue: Hashable, Sendable, CustomDebugStringConvertible {
    case `nil`
    case boolean(Bool)
    case number(Double)
    case string(LuaString)
    case function(LuaFunction)
    case fulluserdata(LuaFullUserdata)
    case lightuserdata(LuaLightUserdata)
    case thread(LuaThread)
    case table(LuaTable)

    public static func userdata(_ ud: some LuaUserdata) -> LuaValue {
        if let fud = ud as? LuaFullUserdata {
            return .fulluserdata(fud)
        } else if let lud = ud as? LuaLightUserdata {
            return .lightuserdata(lud)
        } else {
            return .nil
        }
    }

    public static func object(_ obj: LuaObject) -> LuaValue {
        return .userdata(obj.userdata())
    }

    public static func value(_ val: Bool) -> LuaValue {
        return .boolean(val)
    }

    public static func value(_ val: any BinaryInteger) -> LuaValue {
        return .number(Double(val))
    }

    public static func value(_ val: any BinaryFloatingPoint) -> LuaValue {
        return .number(Double(val))
    }

    public static func value(_ val: [UInt8]) -> LuaValue {
        return .string(.string(val))
    }

    public static func value(_ val: ArraySlice<UInt8>) -> LuaValue {
        return .string(.substring(val))
    }

    public static func value(_ val: String) -> LuaValue {
        return .string(.string(val))
    }

    public static func value(_ val: Substring) -> LuaValue {
        return .string(.string(val.map {$0.asciiValue ?? 0}))
    }

    public static func value(_ val: LuaSwiftFunction) -> LuaValue {
        return .function(.swift(val))
    }

    public static func value(_ val: LuaClosure) -> LuaValue {
        return .function(.lua(val))
    }

    public static func value(_ val: LuaFunction) -> LuaValue {
        return .function(val)
    }

    public static func value(_ val: [LuaValue: LuaValue]) -> LuaValue {
        return .table(LuaTable(from: val))
    }

    public static func value(_ val: LuaTable) -> LuaValue {
        return .table(val)
    }

    public static func value(_ val: LuaThread) -> LuaValue {
        return .thread(val)
    }

    public static func value(_ val: LuaObject) -> LuaValue {
        return .userdata(val.userdata())
    }

    public static func value(_ val: any LuaUserdata) -> LuaValue {
        return .userdata(val)
    }

    public static func value(_ val: LuaValue) -> LuaValue {
        return val
    }

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
        internal static let __pairs = LuaValue.string(.string("__pairs"))
        internal static let __ipairs = LuaValue.string(.string("__ipairs"))
        internal static let arithops: [LuaOpcode.Operation: LuaValue] = [
            .ADD: .string(.string("__add")),
            .SUB: .string(.string("__sub")),
            .MUL: .string(.string("__mul")),
            .DIV: .string(.string("__div")),
            .MOD: .string(.string("__mod")),
            .POW: .string(.string("__pow"))
        ]
    }

    public func metatable(in state: LuaState) async -> LuaTable? {
        switch self {
            case .table(let tbl): return await tbl.metatable
            case .fulluserdata(let ud): return await ud.metatable
            case .lightuserdata: return await state.lightuserdataMetatable
            case .nil: return await state.nilMetatable
            case .boolean: return await state.booleanMetatable
            case .number: return await state.numberMetatable
            case .string: return await state.stringMetatable
            case .function: return await state.functionMetatable
            case .thread: return await state.threadMetatable
        }
    }

    public func metatable(in state: Lua) async -> LuaTable? {
        return await metatable(in: state.thread.luaState)
    }

    public func index(_ index: LuaValue, in state: LuaThread) async throws -> LuaValue {
        switch self {
            case .table(let tbl):
                let v = await tbl[index]
                if v != .nil {
                    return v
                }
            default: break
        }
        if let mt = await metatable(in: state.luaState)?[.Constants.__index] {
            if mt == self {
                throw await Lua.error(in: state, message: "loop in gettable")
            }
            switch mt {
                case .table: return try await mt.index(index, in: state)
                case .function(let fn):
                    let res = try await fn.call(in: state, with: [self, index])
                    return res.first ?? .nil
                default: break
            }
        }
        switch self {
            case .table: return .nil
            default: throw await Lua.error(in: state, message: "attempt to index a \(self.type) value")
        }
    }

    public func index(_ index: LuaValue, in state: Lua) async throws -> LuaValue {
        return try await self.index(index, in: state.thread)
    }

    public func index(_ index: LuaValue, value: LuaValue, in state: LuaThread) async throws {
        if index == .nil {
            throw await Lua.error(in: state, message: "table index is nil")
        }
        switch self {
            case .table(let tbl):
                if await tbl.trySet(index: index, value: value) {
                    return
                }
            default: break
        }
        if let mt = await metatable(in: state.luaState)?[.Constants.__newindex] {
            if mt == self {
                throw await Lua.error(in: state, message: "loop in gettable")
            }
            switch mt {
                case .table:
                    try await mt.index(index, value: value, in: state)
                    return
                case .function(let fn):
                    _ = try await fn.call(in: state, with: [self, index, value])
                    return
                default: break
            }
        }
        switch self {
            case .table(let tbl): await tbl.set(index: index, value: value)
            default: throw await Lua.error(in: state, message: "attempt to index a \(self.type) value")
        }
    }

    public func index(_ index: LuaValue, value: LuaValue, in state: Lua) async throws {
        return try await self.index(index, value: value, in: state.thread)
    }

    public func call(with args: [LuaValue], in state: LuaState) async throws -> [LuaValue] {
        switch self {
            case .function(let fn):
                return try await fn.call(in: state.currentThread, with: args)
            default:
                if let meta = await self.metatable(in: state)?[.Constants.__call] {
                    switch meta {
                        case .function(let fn):
                            var newargs = [self]
                            newargs.append(contentsOf: args)
                            return try await fn.call(in: state.currentThread, with: newargs)
                        default: break
                    }
                }
                throw await Lua.error(in: state.currentThread, message: "attempt to call a \(self.type) value")
        }
    }

    public func call(with args: [LuaValue], in state: Lua) async throws -> [LuaValue] {
        switch self {
            case .function(let fn):
                return try await fn.call(in: state.thread, with: args)
            default:
                if let meta = await self.metatable(in: state)?[.Constants.__call] {
                    switch meta {
                        case .function(let fn):
                            var newargs = [self]
                            newargs.append(contentsOf: args)
                            return try await fn.call(in: state.thread, with: newargs)
                        default: break
                    }
                }
                throw await Lua.error(in: state, message: "attempt to call a \(self.type) value")
        }
    }

    public var type: String {
        switch self {
            case .nil: return "nil"
            case .boolean: return "boolean"
            case .number: return "number"
            case .string: return "string"
            case .function: return "function"
            case .lightuserdata, .fulluserdata: return "userdata"
            case .thread: return "thread"
            case .table: return "table"
        }
    }

    public var toString: String {
        get async {
            switch self {
                case .nil: return "nil"
                case .boolean(let val): return val ? "true" : "false"
                case .number(let val):
                    if let i = Int(exactly: val) {
                        return String(i)
                    }
                    return String(val)
                case .string(let val): return val.string
                case .function(let val):
                    switch val {
                        case .lua(let cl): return "function: \(String(UInt(bitPattern: Unmanaged.passUnretained(cl).toOpaque()), radix: 16))"
                        case .swift(let cl): return "function: \(String(UInt(bitPattern: Unmanaged.passUnretained(cl).toOpaque()), radix: 16))"
                    }
                case .lightuserdata(let val): return "userdata: \(String(UInt(bitPattern: Unmanaged.passUnretained(val.object).toOpaque()), radix: 16))"
                case .fulluserdata(let val): return "\((try? await val.metatable?["__name"].checkString(at: 0)) ?? "userdata"): \(String(UInt(bitPattern: Unmanaged.passUnretained(val).toOpaque()), radix: 16))"
                case .thread(let val): return "thread: \(String(UInt(bitPattern: Unmanaged.passUnretained(val).toOpaque()), radix: 16))"
                case .table(let val): return "\((try? await val.metatable?["__name"].checkString(at: 0)) ?? "table"): \(String(UInt(bitPattern: Unmanaged.passUnretained(val).toOpaque()), radix: 16))"
            }
        }
    }

    public var toBytes: [UInt8] {
        get async {
            switch self {
                case .nil: return "nil"
                case .boolean(let val): return val ? "true" : "false"
                case .number(let val):
                    if let i = Int(exactly: val) {
                        return String(i).bytes
                    }
                    return String(val).bytes
                case .string(let val): return val.bytes
                case .function(let val):
                    switch val {
                        case .lua(let cl): return "function: \(String(UInt(bitPattern: Unmanaged.passUnretained(cl).toOpaque()), radix: 16))"
                        case .swift(let cl): return "function: \(String(UInt(bitPattern: Unmanaged.passUnretained(cl).toOpaque()), radix: 16))"
                    }
                case .lightuserdata(let val): return "userdata: \(String(UInt(bitPattern: Unmanaged.passUnretained(val.object).toOpaque()), radix: 16))"
                case .fulluserdata(let val): return "\((try? await val.metatable?["__name"].checkString(at: 0)) ?? "userdata"): \(String(UInt(bitPattern: Unmanaged.passUnretained(val).toOpaque()), radix: 16))"
                case .thread(let val): return "thread: \(String(UInt(bitPattern: Unmanaged.passUnretained(val).toOpaque()), radix: 16))"
                case .table(let val): return "\((try? await val.metatable?["__name"].checkString(at: 0)) ?? "table"): \(String(UInt(bitPattern: Unmanaged.passUnretained(val).toOpaque()), radix: 16))"
            }
        }
    }

    public var toBool: Bool {
        return self != .nil && self != .boolean(false)
    }

    public var toNumber: Double? {
        switch self {
            case .number(let val): return val
            case .string(let val): return Double(val.string.trimmingSpaces)
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

    public func checkBytes(at index: Int, default defaultValue: [UInt8]? = nil) throws -> [UInt8] {
        if defaultValue != nil && self == .nil {
            return defaultValue!
        }
        if case let .string(val) = self {
            return val.bytes
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

    public func checkUserdata(at index: Int, default defaultValue: (any LuaUserdata)? = nil) throws -> any LuaUserdata {
        if defaultValue != nil && self == .nil {
            return defaultValue!
        }
        if case let .lightuserdata(val) = self {
            return val
        } else if case let .fulluserdata(val) = self {
            return val
        }
        throw Lua.argumentError(at: index, for: self, expected: "userdata")
    }

    public func checkUserdata<T>(at index: Int, as type: T.Type, default defaultValue: T? = nil) throws -> T {
        if defaultValue != nil && self == .nil {
            return defaultValue!
        }
        if case let .lightuserdata(val) = self, let v = val.object as? T {
            return v
        } else if case let .fulluserdata(val) = self, let v = val.object as? T {
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

    public var optional: LuaValue? {
        if self == .nil {return nil}
        return self
    }

    public var debugDescription: String {
        switch self {
            case .nil: return "nil"
            case .boolean(let val): return val ? "true" : "false"
            case .number(let val):
                if let i = Int(exactly: val) {
                    return String(i)
                }
                return String(val)
            case .string(let val): return val.string
            case .function(let val):
                switch val {
                    case .lua(let cl): return "function: \(String(UInt(bitPattern: Unmanaged.passUnretained(cl).toOpaque()), radix: 16))"
                    case .swift(let cl): return "function: \(String(UInt(bitPattern: Unmanaged.passUnretained(cl).toOpaque()), radix: 16))"
                }
            case .lightuserdata(let val): return "userdata: \(String(UInt(bitPattern: Unmanaged.passUnretained(val.object).toOpaque()), radix: 16))"
            case .fulluserdata(let val): return "userdata: \(String(UInt(bitPattern: Unmanaged.passUnretained(val).toOpaque()), radix: 16))"
            case .thread(let val): return "thread: \(String(UInt(bitPattern: Unmanaged.passUnretained(val).toOpaque()), radix: 16))"
            case .table(let val): return "table: \(String(UInt(bitPattern: Unmanaged.passUnretained(val).toOpaque()), radix: 16))"
        }
    }
}
