extension [LuaValue] {
    public subscript(safe index: Int) -> Element {
        guard index >= 0, index < endIndex else {
            return .nil
        }

        return self[index]
    }
}

public class Lua {
    public enum LuaError: Error {
        case runtimeError(message: String)
        case luaError(message: LuaValue)
        case vmError
    }

    public static func argumentError(at index: Int, for val: LuaValue, expected type: String) -> LuaError {
        return LuaError.runtimeError(message: "bad argument #\(index) (expected \(type), got \(val.type))")
    }

    public static func argumentError(at index: Int, in args: [LuaValue], expected type: String) -> LuaError {
        return LuaError.runtimeError(message: "bad argument #\(index) (expected \(type), got \(args[index-1].type))")
    }

    public static func globalTable() -> LuaTable {
        let _G = BaseLibrary().table
        _G["_G"] = .table(_G)
        _G["_VERSION"] = .string(.string("Lua 5.1"))

        return _G
    }

    public let thread: LuaThread

    internal init(in thread: LuaThread) {
        self.thread = thread
    }
}