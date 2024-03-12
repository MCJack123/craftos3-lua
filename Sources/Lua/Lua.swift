public class Lua {
    public enum LuaError: Error {
        case runtimeError(message: String)
        case luaError(message: LuaValue)
        case vmError
        case internalError
    }

    public struct HookFlags: OptionSet {
        public let rawValue: Int

        public static let count    = HookFlags(rawValue: 1 << 0)
        public static let line     = HookFlags(rawValue: 1 << 1)
        public static let call     = HookFlags(rawValue: 1 << 2)
        public static let tailCall = HookFlags(rawValue: 1 << 3)
        public static let `return` = HookFlags(rawValue: 1 << 4)
        public static let anyCall: HookFlags = [.call, .tailCall]

        public init(rawValue: Int) {
            self.rawValue = rawValue
        }
    }

    @frozen
    public struct Debug {
        public enum NameType {
            case global
            case local
            case method
            case field
            case upvalue
            case unknown
        }

        public enum FunctionType {
            case lua
            case swift
            case main
        }

        public struct InfoFlags: OptionSet {
            public let rawValue: Int

            public static let name     = InfoFlags(rawValue: 1 << 0)
            public static let source   = InfoFlags(rawValue: 1 << 1)
            public static let line     = InfoFlags(rawValue: 1 << 2)
            public static let upvalues = InfoFlags(rawValue: 1 << 3)
            public static let tailCall = InfoFlags(rawValue: 1 << 4)
            public static let function = InfoFlags(rawValue: 1 << 5)
            public static let lines    = InfoFlags(rawValue: 1 << 6)

            public static let all: InfoFlags = [.name, .source, .line, .upvalues, .tailCall, .function, .lines]

            public init(rawValue: Int) {
                self.rawValue = rawValue
            }
        }

        public var name: String?
        public var nameWhat: NameType?
        public var what: FunctionType?
        public var source: [UInt8]?
        public var currentLine: Int?
        public var lineDefined: Int?
        public var lastLineDefined: Int?
        public var upvalueCount: Int?
        public var parameterCount: Int?
        public var isVararg: Bool?
        public var isTailCall: Bool?
        public var function: LuaFunction?
        public var validLines: Set<Int>?
        internal init() {}
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
                return LuaError.runtimeError(message: "\(cl.proto.name.string):\(cl.proto.lineinfo[ci.savedpc]): \(text)")
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

    public init(in thread: LuaThread) {
        self.thread = thread
    }

    public func error(_ text: String, at level: Int = 1) -> LuaError {
        return Lua.error(in: thread, message: text, at: level)
    }

    public func argumentError(at index: Int, for val: LuaValue, expected type: String) -> LuaError {
        return self.error("bad argument #\(index) (expected \(type), got \(val.type))", at: 1)
    }

    public func argumentError(at index: Int, in args: LuaArgs, expected type: String) -> LuaError {
        return self.error("bad argument #\(index) (expected \(type), got \(args[index].type))", at: 1)
    }

    private func info(with options: Debug.InfoFlags, in ci: CallInfo?, for function: LuaFunction, at level: Int?) -> Debug {
        var retval = Debug()
        if options.contains(.name) {
            // TODO
            retval.name = "?"
            retval.nameWhat = .unknown
        }
        if options.contains(.source) {
            switch function {
                case .lua(let cl):
                    if let level = level, level == thread.callStack.count - 1 {
                        retval.what = .main
                    } else {
                        retval.what = .lua
                    }
                    retval.source = cl.proto.name
                    retval.lineDefined = Int(cl.proto.lineDefined)
                    retval.lastLineDefined = Int(cl.proto.lastLineDefined)
                case .swift:
                    retval.what = .swift
                    retval.source = "[C]"
                    retval.lineDefined = -1
                    retval.lastLineDefined = -1
            }
        }
        if options.contains(.line) {
            switch function {
                case .lua(let cl):
                    if let ci = ci, ci.savedpc < cl.proto.lineinfo.count {
                        retval.currentLine = Int(cl.proto.lineinfo[ci.savedpc])
                    } else {
                        retval.currentLine = -1
                    }
                case .swift:
                    retval.currentLine = -1
            }
        }
        if options.contains(.upvalues) {
            switch function {
                case .lua(let cl):
                    retval.upvalueCount = cl.proto.upvalues.count
                    retval.parameterCount = Int(cl.proto.numParams)
                    retval.isVararg = cl.proto.isVararg != 0
                case .swift:
                    retval.upvalueCount = 0
                    retval.parameterCount = 0
                    retval.isVararg = true
            }
        }
        if options.contains(.tailCall) {
            if let ci = ci {
                retval.isTailCall = ci.tailcalls > 0
            } else {
                retval.isTailCall = false
            }
        }
        if options.contains(.function) {
            retval.function = function
        }
        if options.contains(.lines) {
            retval.validLines = Set<Int>()
            if case let .lua(cl) = function {
                for l in cl.proto.lineinfo {
                    retval.validLines!.insert(Int(l))
                }
            }
        }
        return retval
    }

    public func info(at level: Int, with options: Debug.InfoFlags = .all) -> Debug? {
        if level < 0 || level >= thread.callStack.count {
            return nil
        }
        let ci = thread.callStack[thread.callStack.count - level - 1]
        return info(with: options, in: ci, for: ci.function, at: level)
    }

    public func info(for function: LuaFunction, with options: Debug.InfoFlags = .all) -> Debug {
        return info(with: options, in: nil, for: function, at: nil)
    }

    public func local(at level: Int, index: Int) throws -> (String, LuaValue)? {
        if level < 0 || level >= thread.callStack.count {
            throw Lua.LuaError.runtimeError(message: "bad argument (level out of range)")
        }
        let ci = thread.callStack[thread.callStack.count - level - 1]
        if index < 0, let vararg = ci.vararg {
            if -index >= vararg.count {
                return nil
            }
            return ("(*vararg)", vararg[-index - 1])
        } else if index > 0 {
            if index > ci.stack.count {
                return nil
            }
            var name = "(*temporary)"
            if case let .lua(cl) = ci.function, index <= cl.proto.locals.count {
                name = cl.proto.locals[index-1].0
            }
            return (name, ci.stack[index-1])
        } else {
            return nil
        }
    }

    public func local(at level: Int, index: Int, value: LuaValue) throws -> String? {
        if level < 0 || level >= thread.callStack.count {
            throw LuaError.runtimeError(message: "bad argument (level out of range)")
        }
        let ci = thread.callStack[thread.callStack.count - level - 1]
        if index < 0 && ci.vararg != nil {
            if -index >= ci.vararg!.count {
                return nil
            }
            ci.vararg![-index - 1] = value
            return "(*vararg)"
        } else if index > 0 {
            if index > ci.stack.count {
                return nil
            }
            ci.stack[index-1] = value
            var name = "(*temporary)"
            if case let .lua(cl) = ci.function, index <= cl.proto.locals.count {
                name = cl.proto.locals[index-1].0
            }
            return name
        } else {
            throw LuaError.internalError
        }
    }

    public func local(in function: LuaFunction, index: Int) -> String? {
        if case let .lua(cl) = function, index < cl.proto.locals.count {
            return cl.proto.locals[index].0
        }
        return nil
    }

    public func upvalue(in function: LuaFunction, index: Int) -> (String?, LuaValue)? {
        if case let .lua(cl) = function, index > 0 && index <= cl.upvalues.count {
            return (cl.proto.upvalues[index-1].2, cl.upvalues[index-1].value)
        }
        return nil
    }

    public func upvalue(in function: LuaFunction, index: Int, value: LuaValue) -> String? {
        if case let .lua(cl) = function, index > 0 && index <= cl.upvalues.count {
            cl.upvalues[index-1].value = value
            return cl.proto.upvalues[index-1].2 ?? ""
        }
        return nil
    }

    public func upvalue(objectIn function: LuaFunction, index: Int) -> LuaUpvalue? {
        if case let .lua(cl) = function, index > 0 && index <= cl.upvalues.count {
            return cl.upvalues[index-1]
        }
        return nil
    }

    public func upvalue(joinFrom fromFunction: LuaFunction, index fromIndex: Int, to toFunction: LuaFunction, index toIndex: Int) throws {
        if case let .lua(cl1) = fromFunction,
            fromIndex > 0 && fromIndex <= cl1.upvalues.count,
            case let .lua(cl2) = toFunction,
            toIndex > 0 && toIndex <= cl2.upvalues.count {
            cl1.upvalues[fromIndex-1] = cl2.upvalues[toIndex-1]
            return
        }
        throw LuaError.internalError
    }

    public func hook() -> (LuaFunction, HookFlags, Int)? {
        if let hook = thread.hookFunction {
            return (hook, thread.hookFlags, thread.hookCount)
        }
        return nil
    }

    public func hook(function: LuaFunction?, for events: HookFlags, count: Int = 0) {
        if let hook = function, !events.isEmpty {
            thread.hookFunction = hook
            thread.hookFlags = events
            thread.hookCount = count
        } else {
            thread.hookFunction = nil
            thread.hookFlags = []
            thread.hookCount = 0
        }
    }
}

@attached(member, names: arbitrary)
@attached(extension, conformances: LuaObject, names: named(userdata))
public macro LuaObject() = #externalMacro(module: "LuaMacros", type: "LuaObjectMacro")

public protocol LuaObject {
    var userdata: LuaUserdata {get}
}
