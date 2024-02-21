public class LuaUpvalue {
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
        get {
            if let stack = stack {
                return stack.stack[index!]
            }
            if let _value = _value {
                return _value
            }
            return .nil // this should never happen
        } set (value) {
            if let stack = stack {
                stack.stack[index!] = value
                return
            }
            _value = value
        }
    }

    internal func close() {
        if let stack = stack {
            _value = stack.stack[index!]
            self.stack = nil
            index = nil
        }
    }
}