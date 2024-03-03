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

    public static func error(in thread: LuaThread, message text: String, at level: Int = 0) -> LuaError {
        let idx = thread.callStack.count - level - 1
        if idx >= 0 && idx < thread.callStack.count {
            let ci = thread.callStack[idx]
            if case let .lua(cl) = ci.function, ci.savedpc < cl.proto.lineinfo.count {
                return LuaError.runtimeError(message: "\(cl.proto.name):\(cl.proto.lineinfo[ci.savedpc]): \(text)")
            }
        }
        return LuaError.runtimeError(message: text)
    }

    public static func error(in state: Lua, message text: String, at level: Int = 1) -> LuaError {
        return error(in: state.thread, message: text, at: level)
    }

    public let thread: LuaThread
    public var state: LuaState {
        return thread.luaState
    }

    internal init(in thread: LuaThread) {
        self.thread = thread
    }
}

@attached(member, names: arbitrary)
@attached(extension, conformances: LuaObject, names: named(userdata))
public macro LuaObject() = #externalMacro(module: "LuaMacros", type: "LuaObjectMacro")

public protocol LuaObject {
    var userdata: LuaUserdata {get}
}
