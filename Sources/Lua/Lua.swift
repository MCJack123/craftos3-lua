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

    /*
    ** {======================================================
    ** Symbolic Execution (from PUC Lua)
    ** =======================================================
    */

    private static func kname(_ p: LuaInterpretedFunction, _ pc: Int, _ c: UInt16) -> String {
        if c > 255 {
            let kvalue = p.constants[c-256]
            if case let .string(s) = kvalue {
                return s.string
            }
        } else {
            if let (name, what) = getobjname(p, pc, UInt8(c)), what == .constant {
                return name
            }
        }
        return "?"
    }
    
    private static func filterpc(_ pc: Int, _ jmptarget: Int) -> Int? {
        if pc < jmptarget {
            return nil
        }
        return pc
    }

    private static func findsetreg(_ p: LuaInterpretedFunction, _ lastpc: Int, _ reg: UInt8) -> Int? {
        var setreg: Int? = nil
        var jmptarget = 0
        for pc in 0..<lastpc {
            let i = p.opcodes[pc]
            switch i {
                case .iABC(let op, let a, let b, _):
                    switch op {
                        case .LOADNIL:
                            if a <= reg && reg <= UInt16(a) + b {
                                setreg = filterpc(pc, jmptarget)
                            }
                        case .TFORCALL:
                            if reg >= a + 2 {
                                setreg = filterpc(pc, jmptarget)
                            }
                        case .CALL, .TAILCALL:
                            if reg >= a {
                                setreg = filterpc(pc, jmptarget)
                            }
                        case .MOVE, .LOADBOOL,.GETUPVAL, .GETTABUP, .GETTABLE,
                             .NEWTABLE, .SELF, .ADD, .SUB, .MUL, .DIV, .MOD, .POW,
                             .UNM, .NOT, .LEN, .CONCAT, .TEST, .TESTSET, .VARARG:
                            if reg == a {
                                setreg = filterpc(pc, jmptarget)
                            }
                        default: break
                    }
                case .iABx(_, let a, _):
                    if reg == a {
                        setreg = filterpc(pc, jmptarget)
                    }
                case .iAsBx(let op, let a, let b):
                    switch op {
                        case .JMP:
                            let dest = pc + 1 + Int(b)
                            if pc < dest && dest <= lastpc && dest > jmptarget {
                                jmptarget = dest
                            }
                        case .FORLOOP, .FORPREP, .TFORLOOP:
                            if reg == a {
                                setreg = filterpc(pc, jmptarget)
                            }
                        default: break
                    }
                case .iAx: break
            }
        }
        return setreg
    }

    private static func getlocalname(_ f: LuaInterpretedFunction, _ n: UInt8, _ pc: Int) -> String? {
        var local_number = n
        var i = 0
        while i < f.locals.count && f.locals[i].1 < pc {
            if pc < f.locals[i].2 {
                local_number -= 1
                if local_number == 0 {
                    return f.locals[i].0
                }
            }
            i += 1
        }
        return nil
    }

    private static func getobjname(_ p: LuaInterpretedFunction, _ lastpc: Int, _ reg: UInt8) -> (String, Debug.NameType)? {
        if let name = getlocalname(p, reg + 1, lastpc) {
            return (name, .local)
        }
        if let pc = findsetreg(p, lastpc, reg) {
            let i = p.opcodes[pc]
            switch i {
                case .iABC(let op, let a, let b, let c):
                    switch op {
                        case .MOVE:
                            if b < a {
                                return getobjname(p, pc, UInt8(b))
                            }
                        case .GETTABUP, .GETTABLE:
                            let k = c, t = b
                            let vn = op == .GETTABLE ? getlocalname(p, UInt8(t + 1), pc) :
                                (t < p.upvalueNames.count ? p.upvalueNames[t] ?? "?" : "?")
                            let name = kname(p, pc, k)
                            return (name, vn == "_ENV" ? .global : .field)
                        case .GETUPVAL:
                            return (b < p.upvalueNames.count ? p.upvalueNames[b] ?? "?" : "?", .upvalue)
                        case .SELF:
                            return (kname(p, pc, c), .method)
                        default: break
                    }
                case .iABx(let op, let a, let bx):
                    switch op {
                        case .LOADK, .LOADKX:
                            let b: UInt32
                            if op == .LOADKX {
                                guard case let .iAx(.EXTRAARG, ax) = p.opcodes[pc+1] else {break}
                                b = ax
                            } else {
                                b = bx
                            }
                            if case let .string(s) = p.constants[b] {
                                return (s.string, .constant)
                            }
                        default: break
                    }
                default: break
            }
        }
        return nil
    }

    private static func getfuncname(_ ci: CallInfo) -> (String, Debug.NameType)? {
        guard case let .lua(cl) = ci.function else {return nil}
        let p = cl.proto
        let pc = ci.savedpc - 1
        let i = p.opcodes[pc]
        switch i {
            case .iABC(let op, let a, _, _):
                switch op {
                    case .CALL, .TAILCALL:
                        return getobjname(p, pc, a)
                    case .TFORCALL:
                        return ("for iterator", .forIterator)
                    case .SELF, .GETTABUP, .GETTABLE:
                        return ("__index", .metamethod)
                    case .SETTABUP, .SETTABLE:
                        return ("__newindex", .metamethod)
                    case .EQ: return ("__eq", .metamethod)
                    case .ADD: return ("__add", .metamethod)
                    case .SUB: return ("__sub", .metamethod)
                    case .MUL: return ("__mul", .metamethod)
                    case .DIV: return ("__div", .metamethod)
                    case .MOD: return ("__mod", .metamethod)
                    case .POW: return ("__pow", .metamethod)
                    case .UNM: return ("__unm", .metamethod)
                    case .LEN: return ("__len", .metamethod)
                    case .LT: return ("__lt", .metamethod)
                    case .LE: return ("__le", .metamethod)
                    case .CONCAT: return ("__concat", .metamethod)
                    default: return nil
                }
            default: return nil
        }
    }

    /* }====================================================== */

    private func info(with options: Debug.InfoFlags, in ci: CallInfo?, previous: CallInfo?, for function: LuaFunction, at level: Int?) -> Debug {
        var retval = Debug()
        if options.contains(.name) {
            if let ci = previous, let (name, what) = Lua.getfuncname(ci) {
                retval.name = name
                retval.nameWhat = what
            } else {
                retval.name = "?"
                retval.nameWhat = .unknown
            }
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
                    if let ci = ci, ci.savedpc-1 < cl.proto.lineinfo.count {
                        retval.currentLine = Int(cl.proto.lineinfo[ci.savedpc-1])
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
        let previous = level == thread.callStack.count - 1 ? nil : thread.callStack[thread.callStack.count - level - 2]
        return info(with: options, in: ci, previous: previous, for: ci.function, at: level)
    }

    public func info(for function: LuaFunction, with options: Debug.InfoFlags = .all) -> Debug {
        return info(with: options, in: nil, previous: nil, for: function, at: nil)
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
