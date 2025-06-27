public actor LuaUpvalue: Equatable {
    private var stack: CallInfo?
    private var index: Int?
    private var _value: LuaValue?

    internal init(in stack: CallInfo, at index: Int) {
        self.stack = stack
        self.index = index
    }

    public init(with value: LuaValue) {
        self._value = value
    }

    public var value: LuaValue {
        get async {
            if let stack = stack {
                return await stack.stack[index!]
            }
            if let _value = _value {
                return _value
            }
            return .nil // this should never happen
        }
    }

    public func set(value: LuaValue) async {
        if let stack = stack {
            await stack.set(at: index!, value: value)
            return
        }
        _value = value
    }

    internal func `in`(stack ci: CallInfo, at pos: Int) -> Bool {
        return stack === ci && index == pos
    }

    internal func close() async {
        if let stack = stack {
            _value = await stack.stack[index!]
            self.stack = nil
            index = nil
        }
    }

    public static func == (lhs: LuaUpvalue, rhs: LuaUpvalue) -> Bool {
        return lhs === rhs
    }
}