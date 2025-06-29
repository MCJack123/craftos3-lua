public struct LuaArgs: Sendable {
    public let args: [LuaValue]
    private let state: Lua?

    public var count: Int {
        return args.count
    }

    public init(_ a: [LuaValue], state: Lua? = nil) {
        args = a
        self.state = state
    }

    private func argumentError(at index: Int, for val: LuaValue, expected type: String) async -> Lua.LuaError {
        if let state = state {
            return await state.argumentError(at: index, for: val, expected: type)
        }
        return Lua.argumentError(at: index, for: val, expected: type)
    }

    public subscript(index: Int) -> LuaValue {
        var val = LuaValue.nil
        if index <= args.count {
            val = args[index-1]
        }
        return val
    }

    public subscript(index: Range<Int>) -> ArraySlice<LuaValue> {
        if index.lowerBound > args.count {
            return ArraySlice<LuaValue>(repeating: .nil, count: index.count)
        } else if index.upperBound > args.count {
            var v = [LuaValue](args[(index.lowerBound - 1)...])
            v.append(contentsOf: [LuaValue](repeating: .nil, count: index.upperBound - args.count))
            return ArraySlice<LuaValue>(v)
        } else {
            return args[(index.lowerBound - 1) ... (index.upperBound - 1)]
        }
    }

    public subscript(index: PartialRangeFrom<Int>) -> ArraySlice<LuaValue> {
        if index.lowerBound > args.count || index.lowerBound == 0 || index.lowerBound <= -args.count {
            return []
        } else if index.lowerBound < 0 {
            return args[(args.count + index.lowerBound)...]
        }
        return args[(index.lowerBound - 1)...]
    }

    public subscript(index: PartialRangeUpTo<Int>) -> ArraySlice<LuaValue> {
        if index.upperBound > args.count {
            var v = args
            v.append(contentsOf: [LuaValue](repeating: .nil, count: index.upperBound - args.count))
            return ArraySlice<LuaValue>(v)
        }
        return args[..<(index.upperBound - 1)]
    }

    public subscript(index: PartialRangeThrough<Int>) -> ArraySlice<LuaValue> {
        if index.upperBound > args.count {
            var v = args
            v.append(contentsOf: [LuaValue](repeating: .nil, count: index.upperBound - args.count + 1))
            return ArraySlice<LuaValue>(v)
        }
        return args[...(index.upperBound - 1)]
    }

    public func checkBoolean(at index: Int, default defaultValue: Bool? = nil) async throws -> Bool {
        var val = LuaValue.nil
        if index <= args.count {
            val = args[index-1]
        }
        if defaultValue != nil && val == .nil {
            return defaultValue!
        }
        if case let .boolean(val) = val {
            return val
        }
        throw await argumentError(at: index, for: val, expected: "boolean")
    }

    public func checkNumber(at index: Int, default defaultValue: Double? = nil) async throws -> Double {
        var val = LuaValue.nil
        if index <= args.count {
            val = args[index-1]
        }
        if defaultValue != nil && val == .nil {
            return defaultValue!
        }
        if case let .number(val) = val {
            return val
        }
        throw await argumentError(at: index, for: val, expected: "number")
    }

    public func checkInt(at index: Int, default defaultValue: Int? = nil) async throws -> Int {
        var val = LuaValue.nil
        if index <= args.count {
            val = args[index-1]
        }
        if defaultValue != nil && val == .nil {
            return defaultValue!
        }
        if case let .number(val) = val {
            return Int(val)
        }
        throw await argumentError(at: index, for: val, expected: "number")
    }

    public func checkString(at index: Int, default defaultValue: String? = nil) async throws -> String {
        var val = LuaValue.nil
        if index <= args.count {
            val = args[index-1]
        }
        if defaultValue != nil && val == .nil {
            return defaultValue!
        }
        if case let .string(val) = val {
            return val.string
        }
        throw await argumentError(at: index, for: val, expected: "string")
    }

    public func checkBytes(at index: Int, default defaultValue: [UInt8]? = nil) async throws -> [UInt8] {
        var val = LuaValue.nil
        if index <= args.count {
            val = args[index-1]
        }
        if defaultValue != nil && val == .nil {
            return defaultValue!
        }
        if case let .string(val) = val {
            return val.bytes
        }
        throw await argumentError(at: index, for: val, expected: "string")
    }

    public func checkTable(at index: Int, default defaultValue: LuaTable? = nil) async throws -> LuaTable {
        var val = LuaValue.nil
        if index <= args.count {
            val = args[index-1]
        }
        if defaultValue != nil && val == .nil {
            return defaultValue!
        }
        if case let .table(val) = val {
            return val
        }
        throw await argumentError(at: index, for: val, expected: "table")
    }

    public func checkFunction(at index: Int, default defaultValue: LuaFunction? = nil) async throws -> LuaFunction {
        var val = LuaValue.nil
        if index <= args.count {
            val = args[index-1]
        }
        if defaultValue != nil && val == .nil {
            return defaultValue!
        }
        if case let .function(val) = val {
            return val
        }
        throw await argumentError(at: index, for: val, expected: "function")
    }

    public func checkThread(at index: Int, default defaultValue: LuaThread? = nil) async throws -> LuaThread {
        var val = LuaValue.nil
        if index <= args.count {
            val = args[index-1]
        }
        if defaultValue != nil && val == .nil {
            return defaultValue!
        }
        if case let .thread(val) = val {
            return val
        }
        throw await argumentError(at: index, for: val, expected: "thread")
    }

    public func checkUserdata(at index: Int, default defaultValue: (any LuaUserdata)? = nil) async throws -> any LuaUserdata {
        var val = LuaValue.nil
        if index <= args.count {
            val = args[index-1]
        }
        if defaultValue != nil && val == .nil {
            return defaultValue!
        }
        if case let .lightuserdata(val) = val {
            return val
        } else if case let .fulluserdata(val) = val {
            return val
        }
        throw await argumentError(at: index, for: val, expected: "userdata")
    }

    public func checkUserdata<T>(at index: Int, as type: T.Type, default defaultValue: T? = nil) async throws -> T {
        var val = LuaValue.nil
        if index <= args.count {
            val = args[index-1]
        }
        if defaultValue != nil && val == .nil {
            return defaultValue!
        }
        if case let .lightuserdata(val) = val, let v = val.object as? T {
            return v
        } else if case let .fulluserdata(val) = val, let v = val.object as? T {
            return v
        }
        throw await argumentError(at: index, for: val, expected: String(reflecting: T.self))
    }
}
