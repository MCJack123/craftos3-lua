public struct LuaArgs {
    public let args: [LuaValue]
    private let state: Lua?

    public var count: Int {
        return args.count
    }

    public init(_ a: [LuaValue], state: Lua? = nil) {
        args = a
        self.state = state
    }

    private func argumentError(at index: Int, for val: LuaValue, expected type: String) -> Lua.LuaError {
        if let state = state {
            return state.argumentError(at: index, for: val, expected: type)
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
        if index.lowerBound > args.count {
            return []
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

    public func checkBoolean(at index: Int, default defaultValue: Bool? = nil) throws -> Bool {
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
        throw argumentError(at: index, for: val, expected: "boolean")
    }

    public func checkNumber(at index: Int, default defaultValue: Double? = nil) throws -> Double {
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
        throw argumentError(at: index, for: val, expected: "number")
    }

    public func checkInt(at index: Int, default defaultValue: Int? = nil) throws -> Int {
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
        throw argumentError(at: index, for: val, expected: "number")
    }

    public func checkString(at index: Int, default defaultValue: String? = nil) throws -> String {
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
        throw argumentError(at: index, for: val, expected: "string")
    }

    public func checkBytes(at index: Int, default defaultValue: [UInt8]? = nil) throws -> [UInt8] {
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
        throw argumentError(at: index, for: val, expected: "string")
    }

    public func checkTable(at index: Int, default defaultValue: LuaTable? = nil) throws -> LuaTable {
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
        throw argumentError(at: index, for: val, expected: "table")
    }

    public func checkFunction(at index: Int, default defaultValue: LuaFunction? = nil) throws -> LuaFunction {
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
        throw argumentError(at: index, for: val, expected: "function")
    }

    public func checkThread(at index: Int, default defaultValue: LuaThread? = nil) throws -> LuaThread {
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
        throw argumentError(at: index, for: val, expected: "thread")
    }

    public func checkUserdata(at index: Int, default defaultValue: LuaUserdata? = nil) throws -> LuaUserdata {
        var val = LuaValue.nil
        if index <= args.count {
            val = args[index-1]
        }
        if defaultValue != nil && val == .nil {
            return defaultValue!
        }
        if case let .userdata(val) = val {
            return val
        }
        throw argumentError(at: index, for: val, expected: "userdata")
    }

    public func checkUserdata<T>(at index: Int, as type: T.Type, default defaultValue: T? = nil) throws -> T {
        var val = LuaValue.nil
        if index <= args.count {
            val = args[index-1]
        }
        if defaultValue != nil && val == .nil {
            return defaultValue!
        }
        if case let .userdata(val) = val, let v = val.object as? T {
            return v
        }
        throw argumentError(at: index, for: val, expected: String(reflecting: T.self))
    }
}
