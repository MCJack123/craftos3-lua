public final class Lua: Sendable {
    public enum LuaError: Error {
        case runtimeError(message: String)
        case luaError(message: LuaValue)
        case vmError
        case internalError
    }

    public struct HookFlags: OptionSet, Sendable {
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
    public struct Debug: Sendable {
        public enum NameType: Sendable {
            case constant
            case global
            case field
            case forIterator
            case local
            case metamethod
            case method
            case upvalue
            case unknown
        }

        public enum FunctionType: Sendable {
            case lua
            case swift
            case main
        }

        public struct InfoFlags: OptionSet, Sendable {
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
        public var short_src: String?
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

    public static func error(in thread: LuaThread, message text: String, at level: Int = 0) async -> LuaError {
        return await thread.error(message: text, at: level)
    }

    public static func error(in state: Lua, message text: String, at level: Int = 1) async -> LuaError {
        return await error(in: state.thread, message: text, at: level)
    }

    public let thread: LuaThread
    public var luaState: LuaState {
        return thread.luaState
    }

    public init(in thread: LuaThread) {
        self.thread = thread
    }

    public func error(_ text: String, at level: Int = 1) async -> LuaError {
        return await thread.error(message: text, at: level)
    }

    public func argumentError(at index: Int, for val: LuaValue, expected type: String) async -> LuaError {
        return await self.error("bad argument #\(index) (expected \(type), got \(val.type))", at: 1)
    }

    public func argumentError(at index: Int, in args: LuaArgs, expected type: String) async -> LuaError {
        return await self.error("bad argument #\(index) (expected \(type), got \(args[index].type))", at: 1)
    }

    public static func shortSource(for cl: LuaClosure) -> String {
        if cl.proto.name.first == "@" {
            if cl.proto.name.count > 61 {
                return "..." + [UInt8](cl.proto.name[cl.proto.name.index(cl.proto.name.endIndex, offsetBy: -57)..<cl.proto.name.endIndex]).string
            } else {
                var s = cl.proto.name.string
                s.removeFirst()
                return s
            }
        } else if cl.proto.name.first == "=" {
            let name = cl.proto.name.string
            return String(name[name.index(after: name.startIndex)..<(name.index(name.startIndex, offsetBy: 61, limitedBy: name.endIndex) ?? name.endIndex)])
        } else {
            let name = [UInt8](cl.proto.name.prefix(while: {$0 != "\n"})).string
            if name.count > 49 || cl.proto.name.contains("\n") {
                return "[string \"\(name[name.startIndex..<(name.index(name.startIndex, offsetBy: 46, limitedBy: name.endIndex) ?? name.endIndex)])...\"]"
            } else {
                return "[string \"\(name)\"]"
            }
        }
    }

    public func info(at level: Int, with options: Debug.InfoFlags = .all) async -> Debug? {
        return await thread.info(at: level, with: options)
    }

    public func info(for function: LuaFunction, with options: Debug.InfoFlags = .all) async -> Debug {
        return await thread.info(with: options, in: nil, previous: nil, for: function, at: nil)
    }

    public func local(at level: Int, index: Int) async throws -> (String, LuaValue)? {
        return try await thread.local(at: level, index: index)
    }

    public func local(at level: Int, index: Int, value: LuaValue) async throws -> String? {
        return try await thread.local(at: level, index: index, value: value)
    }

    public func local(in function: LuaFunction, index: Int) -> String? {
        if case let .lua(cl) = function, index < cl.proto.locals.count {
            return cl.proto.locals[index].0
        }
        return nil
    }

    public func upvalue(in function: LuaFunction, index: Int) async -> (String?, LuaValue)? {
        if case let .lua(cl) = function, let uv = await cl.upvalue(index)?.value {
            return (cl.proto.upvalues[index-1].2, uv)
        }
        return nil
    }

    public func upvalue(in function: LuaFunction, index: Int, value: LuaValue) async -> String? {
        if case let .lua(cl) = function, let uv = await cl.upvalue(index) {
            await uv.set(value: value)
            return cl.proto.upvalues[index-1].2 ?? ""
        }
        return nil
    }

    public func upvalue(objectIn function: LuaFunction, index: Int) async -> LuaUpvalue? {
        if case let .lua(cl) = function {
            return await cl.upvalue(index)
        }
        return nil
    }

    public func upvalue(joinFrom fromFunction: LuaFunction, index fromIndex: Int, to toFunction: LuaFunction, index toIndex: Int) async throws {
        if case let .lua(cl1) = fromFunction, case let .lua(cl2) = toFunction, let uv = await cl2.upvalue(toIndex) {
            try await cl1.upvalue(fromIndex, value: uv)
            return
        }
        throw LuaError.internalError
    }

    public func hook() async -> (LuaFunction, HookFlags, Int)? {
        return await thread.hook()
    }

    public func hook(function: LuaFunction?, for events: HookFlags, count: Int = 0) async {
        return await thread.hook(function: function, for: events, count: count)
    }

    public func global(named name: String) async -> LuaValue {
        return await luaState.global(named: name)
    }

    public func global(named name: String, value: LuaValue) async {
        await luaState.global(named: name, value: value)
    }
}

@attached(member, names: arbitrary)
@attached(extension, conformances: LuaObject, names: named(userdata))
public macro LuaObject() = #externalMacro(module: "LuaMacros", type: "LuaObjectMacro")

public protocol LuaObject: Sendable {
    func userdata() -> any LuaUserdata
}
