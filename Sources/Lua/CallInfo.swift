public class CallInfo {
    internal var function: LuaFunction
    internal var stack: [LuaValue]
    internal var savedpc: Int = 0
    internal let numResults: Int?
    internal var tailcalls: Int = 0
    internal var top: Int = 0
    internal var vararg: [LuaValue]? = nil

    internal init(for cl: LuaFunction, numResults nRes: Int?, stackSize: Int = 0) {
        function = cl
        numResults = nRes
        stack = [LuaValue](repeating: .nil, count: stackSize)
    }
}