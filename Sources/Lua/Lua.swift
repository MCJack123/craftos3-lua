public class Lua {
    public enum LuaError: Error {
        case runtimeError(message: String)
        case luaError(message: LuaValue)
        case vmError
        case internalError
    }

    public static func argumentError(at index: Int, for val: LuaValue, expected type: String) -> LuaError {
        return LuaError.runtimeError(message: "bad argument #\(index) (expected \(type), got \(val.type))")
    }

    public static func argumentError(at index: Int, in args: LuaArgs, expected type: String) -> LuaError {
        return LuaError.runtimeError(message: "bad argument #\(index) (expected \(type), got \(args[index].type))")
    }

    public static func globalTable() -> LuaTable {
        let _G = BaseLibrary().table
        _G["_G"] = .table(_G)
        _G["_VERSION"] = .string(.string("Lua 5.2"))
        _G["bit32"] = .table(Bit32Library().table)
        _G["coroutine"] = .table(CoroutineLibrary().table)
        _G["math"] = .table(MathLibrary().table)
        _G["string"] = .table(StringLibrary().table)
        _G["table"] = .table(TableLibrary().table)
        return _G
    }

    public let thread: LuaThread

    internal init(in thread: LuaThread) {
        self.thread = thread
    }
}