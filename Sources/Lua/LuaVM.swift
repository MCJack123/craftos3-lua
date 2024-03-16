import LibC

extension Array {
    subscript(index: UInt8) -> Array.Element {get {return self[Int(index)]} set (value) {self[Int(index)] = value}}
    subscript(index: UInt16) -> Array.Element {get {return self[Int(index)]} set (value) {self[Int(index)] = value}}
    subscript(index: UInt32) -> Array.Element {get {return self[Int(index)]} set (value) {self[Int(index)] = value}}
}

public actor CallInfo {
    internal var function: LuaFunction
    internal var stack: [LuaValue]
    internal var savedpc: Int = 0
    internal let numResults: Int?
    internal var tailcalls: Int = 0
    internal var top: Int = 0
    internal var vararg: [LuaValue]? = nil
    internal var openUpvalues = [Int: LuaUpvalue]()

    internal init(for cl: LuaFunction, numResults nRes: Int?, stackSize: Int = 0) {
        function = cl
        numResults = nRes
        stack = [LuaValue](repeating: .nil, count: stackSize)
    }

    internal static func execute(closure: LuaClosure, with args: [LuaValue], numResults: Int?, state: LuaThread) async throws -> [LuaValue] {
        //print("Starting interpreter with args", args)
        return try await CallInfo(for: .lua(closure), numResults: numResults, stackSize: Int(closure.proto.stackSize))
            .startExecute(closure: closure, with: args, state: state)
    }

    private func startExecute(closure: LuaClosure, with args: [LuaValue], state: LuaThread) async throws -> [LuaValue] {
        var newargs = args
        if newargs.count < closure.proto.numParams {
            newargs.append(contentsOf: [LuaValue](repeating: .nil, count: Int(closure.proto.numParams) - args.count))
        } else if newargs.count > closure.proto.numParams {
            newargs = [LuaValue](newargs[0..<Int(closure.proto.numParams)])
        }
        self.stack.replaceSubrange(0..<Int(closure.proto.numParams), with: newargs)
        if closure.proto.isVararg != 0 {
            if args.count > closure.proto.numParams {
                self.vararg = [LuaValue](args[Int(closure.proto.numParams)...])
            } else {
                self.vararg = []
            }
        }
        if self.stack.count < closure.proto.stackSize {
            self.stack.append(contentsOf: [LuaValue](repeating: .nil, count: Int(closure.proto.stackSize) - self.stack.count))
        }
        state.callStack.append(self)
        if let hook = state.hookFunction, state.hookFlags.contains(.call) {
            _ = try await hook.call(in: state, with: [.string(.string("call"))])
        }
        return try await self.execute(state: state)
    }

    private func finishReturn(with res: [LuaValue], state: LuaThread) async throws -> [LuaValue] {
        var res = res
        switch self.function {
            case .lua(let newcl):
                if let numResults = self.numResults {
                    if res.count < numResults {res.append(contentsOf: [LuaValue](repeating: .nil, count: numResults - res.count))}
                    else if res.count > numResults {res = [LuaValue](res[0..<numResults])}
                    self.stack.replaceSubrange(self.top..<(self.top + res.count), with: res)
                } else {
                    self.stack.append(contentsOf: res)
                    if self.stack.count < newcl.proto.stackSize {
                        self.stack.append(contentsOf: [LuaValue](repeating: .nil, count: Int(newcl.proto.stackSize) - self.stack.count))
                    }
                }
                //print("Results:", res)
                self.top += res.count
                return try await self.execute(state: state, pc: self.savedpc)
            case .swift:
                return res
        }
    }

    private func execute(state: LuaThread, pc: Int = 0, tailcall: Bool = false) async throws -> [LuaValue] {
        var pc = pc
        if tailcall {self.tailcalls += 1}
        if case let .lua(cl) = self.function {
            //print("Entering function \(cl) [\(nexec)]")
            let insts = cl.proto.opcodes
            let constants = cl.proto.constants
            while true {
                if !state.luaState.tablesToBeFinalized.isEmpty {
                    for t in state.luaState.tablesToBeFinalized {
                        if let mt = t.metatable, case let .function(gc) = mt["__gc"] {
                            _ = try await gc.call(in: state, with: [.table(t)])
                        }
                    }
                    state.luaState.tablesToBeFinalized = []
                }
                if state.hookCount > 0 {
                    state.hookCountLeft -= 1
                }
                if let hook = state.hookFunction, state.allowHooks {
                    if state.hookFlags.contains(.count) && state.hookCount > 0 && state.hookCountLeft == 0 {
                        state.allowHooks = false
                        defer {state.allowHooks = true}
                        _ = try await hook.call(in: state, with: [.string(.string("count"))])
                        state.hookCountLeft = state.hookCount
                    }
                    if state.hookFlags.contains(.line) && (pc == 0 || (pc < cl.proto.lineinfo.count && cl.proto.lineinfo[self.savedpc] != cl.proto.lineinfo[pc])) {
                        state.allowHooks = false
                        defer {state.allowHooks = true}
                        _ = try await hook.call(in: state, with: [.string(.string("line")), .number(Double(cl.proto.lineinfo[pc]))])
                    }
                }
                let inst = insts[pc]
                self.savedpc = pc
                //print(cl.proto.lineinfo[pc], pc + 1, inst)
                pc += 1
                switch inst {
                    case .iABC(let op, let a, var b, let c):
                        //print(op, a, b, c)
                        lazy var rkb = (b & 0x100) != 0 ? constants[b & 0xFF] : self.stack[b]
                        lazy var rkc = (c & 0x100) != 0 ? constants[c & 0xFF] : self.stack[c]
                        switch op {
                            case .MOVE:
                                self.stack[a] = self.stack[b]
                            case .LOADKX:
                                let extraarg = insts[pc]
                                pc += 1
                                guard case let .iAx(op2, ax) = extraarg else {
                                    throw Lua.LuaError.vmError
                                }
                                if op2 != .EXTRAARG {
                                    throw Lua.LuaError.vmError
                                }
                                self.stack[a] = constants[ax]
                            case .LOADBOOL:
                                self.stack[a] = .boolean(b != 0)
                                if c != 0 {pc += 1}
                            case .LOADNIL:
                                for i in Int(a)...Int(a)+Int(b) {
                                    self.stack[i] = .nil
                                }
                            case .GETUPVAL:
                                self.stack[a] = cl.upvalues[b].value
                            case .GETTABUP:
                                if b >= cl.upvalues.count {
                                    throw Lua.error(in: state, message: "attempt to index upvalue '?' (a nil value)")
                                }
                                self.stack[a] = try await cl.upvalues[b].value.index(rkc, in: state)
                            case .GETTABLE:
                                self.stack[a] = try await self.stack[b].index(rkc, in: state)
                            case .SETUPVAL:
                                cl.upvalues[b].value = self.stack[a]
                            case .SETTABUP:
                                if a >= cl.upvalues.count {
                                    throw Lua.error(in: state, message: "attempt to index upvalue '?' (a nil value)")
                                }
                                try await cl.upvalues[a].value.index(rkb, value: rkc, in: state)
                            case .SETTABLE:
                                try await self.stack[a].index(rkb, value: rkc, in: state)
                            case .NEWTABLE:
                                let arrsz = (b >> 3) == 0 ? b & 7 : (8 | (b & 7)) << ((b >> 3) - 1)
                                let tabsz = (c >> 3) == 0 ? c & 7 : (8 | (c & 7)) << ((c >> 3) - 1)
                                self.stack[a] = .table(LuaTable(hash: Int(tabsz), array: Int(arrsz), state: state.luaState))
                            case .SELF:
                                self.stack[a+1] = self.stack[b]
                                self.stack[a] = try await self.stack[b].index(rkc, in: state)
                            case .ADD, .SUB, .MUL, .DIV, .MOD, .POW:
                                self.stack[a] = try await CallInfo.arith(op: op, rkb, rkc, state: state)
                            case .UNM:
                                if let n = self.stack[b].toNumber {
                                    self.stack[a] = .number(-n)
                                } else if let mt = self.stack[b].metatable(in: state.luaState)?.metatable?[.Constants.__unm].optional {
                                    switch mt {
                                        case .function(let fn):
                                            let args = [self.stack[b]]
                                            let res = try await fn.call(in: state, with: args)
                                            self.stack[a] = res.first ?? .nil
                                        default: throw Lua.error(in: state, message: "attempt to perform arithmetic on a \(self.stack[b].type) value")
                                    }
                                } else {
                                    throw Lua.error(in: state, message: "attempt to perform arithmetic on a \(self.stack[b].type) value")
                                }
                            case .NOT:
                                self.stack[a] = .boolean(!self.stack[b].toBool)
                            case .LEN:
                                switch self.stack[b] {
                                    case .string(let s): self.stack[a] = .number(Double(s.string.count))
                                    default:
                                        if let mt = self.stack[b].metatable(in: state.luaState)?.metatable?[.Constants.__len] {
                                            switch mt {
                                                case .function(let fn):
                                                    let args = [self.stack[b]]
                                                    let res = try await fn.call(in: state, with: args)
                                                    self.stack[a] = res.first ?? .nil
                                                default: throw Lua.error(in: state, message: "attempt to perform arithmetic on a \(self.stack[b].type) value")
                                            }
                                        } else if case let .table(tbl) = self.stack[b] {
                                            self.stack[a] = .number(Double(tbl.count))
                                        } else {
                                            throw Lua.error(in: state, message: "attempt to get length of a \(self.stack[b].type) value")
                                        }
                                }
                            case .CONCAT:
                                let args = self.stack[Int(b)...Int(c)]
                                self.stack[a] = try await CallInfo.concat(strings: args, in: state)
                            case .EQ:
                                let res: Bool
                                if rkb == rkc {
                                    res = true
                                } else if rkb.type == rkc.type,
                                    let mt = rkb.metatable(in: state.luaState)?[.Constants.__eq],
                                    let mt2 = rkc.metatable(in: state.luaState)?[.Constants.__eq],
                                    mt == mt2, case let .function(fn) = mt {
                                    res = try await fn.call(in: state, with: [rkb, rkc]).first?.toBool ?? false
                                } else {
                                    res = false
                                }
                                if res != (a != 0) {pc += 1}
                            case .LT:
                                let res: Bool
                                if case let .number(nb) = rkb, case let .number(nc) = rkc {
                                    res = nb < nc
                                } else if case let .string(sb) = rkb, case let .string(sc) = rkc {
                                    res = sb < sc
                                } else if let mt = rkb.metatable(in: state.luaState)?[.Constants.__lt], case let .function(fn) = mt {
                                    let v = try await fn.call(in: state, with: [rkb, rkc])
                                    res = v.first?.toBool ?? false
                                } else if let mt = rkc.metatable(in: state.luaState)?[.Constants.__lt], case let .function(fn) = mt {
                                    let v = try await fn.call(in: state, with: [rkb, rkc])
                                    res = v.first?.toBool ?? false
                                } else if case .number = rkb {
                                    throw Lua.error(in: state, message: "attempt to compare a \(rkc.type) value")
                                } else {
                                    throw Lua.error(in: state, message: "attempt to compare a \(rkb.type) value")
                                }
                                if res != (a != 0) {pc += 1}
                            case .LE:
                                let res: Bool
                                if case let .number(nb) = rkb, case let .number(nc) = rkc {
                                    res = nb <= nc
                                } else if case let .string(sb) = rkb, case let .string(sc) = rkc {
                                    res = sb <= sc
                                } else if let mt = rkb.metatable(in: state.luaState)?[.Constants.__le], case let .function(fn) = mt {
                                    let v = try await fn.call(in: state, with: [rkb, rkc])
                                    res = v.first?.toBool ?? false
                                } else if let mt = rkc.metatable(in: state.luaState)?[.Constants.__le], case let .function(fn) = mt {
                                    let v = try await fn.call(in: state, with: [rkb, rkc])
                                    res = v.first?.toBool ?? false
                                } else if let mt = rkb.metatable(in: state.luaState)?[.Constants.__lt], case let .function(fn) = mt {
                                    let v = try await fn.call(in: state, with: [rkc, rkb])
                                    res = !(v.first?.toBool ?? false)
                                } else if let mt = rkc.metatable(in: state.luaState)?[.Constants.__lt], case let .function(fn) = mt {
                                    let v = try await fn.call(in: state, with: [rkc, rkb])
                                    res = !(v.first?.toBool ?? false)
                                } else if case .number = rkb {
                                    throw Lua.error(in: state, message: "attempt to compare a \(rkc.type) value")
                                } else {
                                    throw Lua.error(in: state, message: "attempt to compare a \(rkb.type) value")
                                }
                                if res != (a != 0) {pc += 1}
                            case .TEST:
                                if !(self.stack[a].toBool == (c != 0)) {pc += 1}
                            case .TESTSET:
                                if self.stack[b].toBool == (c != 0) {
                                    self.stack[a] = self.stack[b]
                                } else {
                                    pc += 1
                                }
                            case .CALL:
                                if let newci = try await call(at: Int(a), args: b == 0 ? nil : Int(b - 1), returns: c == 0 ? nil : Int(c - 1), state: state, tailCall: false) {
                                    self.savedpc = pc
                                    return try await newci.execute(state: state)
                                }
                            case .TAILCALL:
                                _ = state.callStack.popLast()
                                if let newci = try await call(at: Int(a), args: b == 0 ? nil : Int(b - 1), returns: self.numResults, state: state, tailCall: true) {
                                    return try await newci.execute(state: state, tailcall: true)
                                } else {
                                    state.callStack.append(self) // immediately removed
                                    b = UInt16(self.numResults != nil ? self.numResults! + 1 : 0)
                                    fallthrough
                                }
                            case .RETURN:
                                if let hook = state.hookFunction, state.allowHooks && state.hookFlags.contains(.return) {
                                    state.allowHooks = false
                                    defer {state.allowHooks = true}
                                    _ = try await hook.call(in: state, with: [.string(.string("return"))])
                                }
                                _ = state.callStack.popLast()
                                var res: [LuaValue]
                                if b == 0 {
                                    res = [LuaValue](self.stack[Int(a)..<self.top])
                                } else {
                                    res = [LuaValue](self.stack[Int(a)..<Int(a)+Int(b-1)])
                                }
                                if state.callStack.isEmpty {
                                    //print("Results:", res)
                                    return res
                                }
                                return try await state.callStack.last!.finishReturn(with: res, state: state)
                            case .TFORCALL:
                                let fn: LuaFunction
                                switch self.stack[a] {
                                    case .function(let _fn): fn = _fn
                                    default:
                                        guard let mt = self.stack[a].metatable(in: state.luaState)?[.Constants.__call] else {throw Lua.error(in: state, message: "attempt to call a \(self.stack[a].type) value")}
                                        guard case let .function(_fn) = mt else {throw Lua.error(in: state, message: "attempt to call a \(self.stack[a].type) value")}
                                        fn = _fn
                                }
                                let args = [self.stack[a+1], self.stack[a+2]]
                                var res = try await fn.call(in: state, with: args)
                                if res.count < c {res.append(contentsOf: [LuaValue](repeating: .nil, count: Int(c) - res.count))}
                                else if res.count > c {res = [LuaValue](res[0..<Int(c)])}
                                self.stack.replaceSubrange((Int(a) + 3) ... (Int(a) + 2 + Int(c)), with: res)
                            case .SETLIST:
                                let _c: UInt32
                                if c == 0 {
                                    guard case let .iAx(_, ax) = insts[pc] else {
                                        throw Lua.LuaError.vmError
                                    }
                                    _c = ax
                                    pc += 1
                                } else {
                                    _c = UInt32(c)
                                }
                                let offset = Int(_c - 1) * 50
                                guard case let .table(tbl) = self.stack[a] else {throw Lua.LuaError.vmError}
                                let _b: Int
                                if b == 0 {
                                    _b = self.top - Int(a) - 1
                                } else {
                                    _b = Int(b)
                                }
                                for j in 0..<_b {
                                    tbl[Int(offset + j + 1)] = self.stack[Int(a) + Int(j) + 1]
                                }
                            case .VARARG:
                                if b == 0 {
                                    if let vararg = self.vararg {
                                        self.stack = [LuaValue](self.stack[0..<Int(a)])
                                        self.stack.append(contentsOf: vararg)
                                        self.top = self.stack.count
                                        if self.stack.count < cl.proto.stackSize {
                                            self.stack.append(contentsOf: [LuaValue](repeating: .nil, count: Int(cl.proto.stackSize) - self.stack.count))
                                        }
                                    } else {
                                        self.top = Int(a)
                                    }
                                } else if let vararg = self.vararg {
                                    for i in 0..<(Int(b) - 1) {
                                        self.stack[Int(a) + i] = i < vararg.count ? vararg[i] : .nil
                                    }
                                } else {
                                    for i in 0..<(Int(b) - 1) {
                                        self.stack[Int(a) + i] = .nil
                                    }
                                }
                            default: throw Lua.LuaError.vmError
                        }
                    case .iABx(let op, let a, let bx):
                        //print(op, a, bx)
                        switch op {
                            case .LOADK:
                                self.stack[a] = constants[bx]
                            case .CLOSURE:
                                let proto = cl.proto.prototypes[bx]
                                var upvalues = [LuaUpvalue]()
                                for upval in proto.upvalues {
                                    if upval.0 != 0 {
                                        if let uv = self.openUpvalues[Int(upval.1)] {
                                            upvalues.append(uv)
                                        } else {
                                            let uv = LuaUpvalue(in: self, at: Int(upval.1))
                                            upvalues.append(uv)
                                            self.openUpvalues[Int(upval.1)] = uv
                                        }
                                    } else {
                                        upvalues.append(cl.upvalues[upval.1])
                                    }
                                }
                                self.stack[a] = .function(.lua(LuaClosure(for: proto, with: upvalues)))
                            default: throw Lua.LuaError.vmError
                        }
                    case .iAsBx(let op, let a, let sbx):
                        //print(op, a, sbx)
                        switch op {
                            case .JMP:
                                pc += Int(sbx)
                                if a > 0 {
                                    for j in (Int(a) - 1) ..< self.stack.count {
                                        if let uv = self.openUpvalues[j] {
                                            uv.close()
                                            self.openUpvalues[j] = nil
                                        }
                                    }
                                }
                            case .FORPREP:
                                guard case let .number(initial) = self.stack[a] else {throw Lua.error(in: state, message: "'for' initial value must be a number")}
                                guard case .number = self.stack[a + 1] else {throw Lua.error(in: state, message: "'for' initial value must be a number")}
                                guard case let .number(step) = self.stack[a + 2] else {throw Lua.error(in: state, message: "'for' initial value must be a number")}
                                self.stack[a] = .number(initial - step)
                                pc += Int(sbx)
                            case .FORLOOP:
                                guard case var .number(value) = self.stack[a] else {throw Lua.error(in: state, message: "'for' initial value must be a number")}
                                guard case let .number(limit) = self.stack[a + 1] else {throw Lua.error(in: state, message: "'for' initial value must be a number")}
                                guard case let .number(step) = self.stack[a + 2] else {throw Lua.error(in: state, message: "'for' initial value must be a number")}
                                value += step
                                self.stack[a] = .number(value)
                                if step > 0 ? value <= limit : value >= limit {
                                    self.stack[a + 3] = .number(value)
                                    pc += Int(sbx)
                                }
                            case .TFORLOOP:
                                if self.stack[a + 1] != .nil {
                                    self.stack[a] = self.stack[a + 1]
                                    pc += Int(sbx)
                                }
                            default: throw Lua.LuaError.vmError
                        }
                    case .iAx(let op, _):
                        switch op {
                            case .EXTRAARG:
                                break // do nothing
                            default: throw Lua.LuaError.vmError
                        }
                }
            }
        } else {
            throw Lua.LuaError.vmError
        }
    }

    private func handleArgs(in cl: LuaClosure, argv: inout [LuaValue]) {
        if argv.count > cl.proto.numParams {
            if cl.proto.isVararg != 0 {
                self.vararg = [LuaValue](argv[Int(cl.proto.numParams)...])
            }
            argv = [LuaValue](argv[0..<Int(cl.proto.numParams)])
        } else if argv.count < cl.proto.numParams {
            argv.append(contentsOf: [LuaValue](repeating: .nil, count: Int(cl.proto.numParams) - argv.count))
        }
        if cl.proto.isVararg != 0 && self.vararg == nil {
            self.vararg = [LuaValue]()
        }
        //print("Arguments:", argv, nextci.vararg)
        self.stack.replaceSubrange(0..<Int(cl.proto.numParams), with: argv)
    }

    private func call(function fn: LuaFunction, at idx: Int, args: Int?, returns: Int?, state: LuaThread, tailCall: Bool) async throws -> CallInfo? {
        switch fn {
            case .lua(let cl):
                let nextci = CallInfo(for: fn, numResults: returns, stackSize: Int(cl.proto.stackSize))
                var argv = args != nil ? (args == 0 ? [] : [LuaValue](self.stack[(idx + 1) ... (idx + args!)])) : [LuaValue](self.stack[(idx+1)..<self.top])
                await nextci.handleArgs(in: cl, argv: &argv)
                self.top = idx
                if returns == nil {
                    self.stack = [LuaValue](self.stack[0..<idx])
                }
                state.callStack.append(nextci)
                if let hook = state.hookFunction, state.allowHooks && state.hookFlags.contains(tailCall ? .tailCall : .call) {
                    state.allowHooks = false
                    defer {state.allowHooks = true}
                    _ = try await hook.call(in: state, with: [.string(.string(tailCall ? "tail call" : "call"))])
                }
                return nextci
            case .swift(let sfn):
                state.callStack.append(CallInfo(for: fn, numResults: returns, stackSize: 0))
                let argv = args != nil ? (args == 0 ? [] : [LuaValue](self.stack[(idx + 1) ... (idx + args!)])) : [LuaValue](self.stack[(idx+1)..<self.top])
                //print("Arguments:", argv)
                if let hook = state.hookFunction, state.allowHooks && state.hookFlags.contains(tailCall ? .tailCall : .call) {
                    state.allowHooks = false
                    defer {state.allowHooks = true}
                    _ = try await hook.call(in: state, with: [.string(.string(tailCall ? "tail call" : "call"))])
                }
                let L = Lua(in: state)
                var res = try await sfn.body(L, LuaArgs(argv, state: L))
                if !tailCall, let hook = state.hookFunction, state.allowHooks && state.hookFlags.contains(.return) {
                    state.allowHooks = false
                    defer {state.allowHooks = true}
                    _ = try await hook.call(in: state, with: [.string(.string("return"))])
                }
                //print("Results:", res)
                if let returns = returns {
                    if res.count > returns {res = [LuaValue](res[0..<returns])}
                    else if res.count < returns {res.append(contentsOf: [LuaValue](repeating: .nil, count: returns - res.count))}
                    self.stack.replaceSubrange(idx ..< min(idx + returns, self.stack.count), with: res)
                    self.top = min(idx + returns, self.stack.count)
                } else {
                    let oldsz = self.stack.count
                    self.stack = [LuaValue](self.stack[0..<idx])
                    self.stack.append(contentsOf: res)
                    if self.stack.count < oldsz {
                        self.stack.append(contentsOf: [LuaValue](repeating: .nil, count: oldsz - self.stack.count))
                    }
                    self.top = idx + res.count
                }
                state.callStack.removeLast()
                return nil
        }
    }

    internal func call(at idx: Int, args: Int?, returns: Int?, state: LuaThread, tailCall: Bool = false) async throws -> CallInfo? {
        switch self.stack[idx] {
            case .function(let fn):
                return try await call(function: fn, at: idx, args: args, returns: returns, state: state, tailCall: tailCall)
            default:
                if let meta = self.stack[idx].metatable(in: state.luaState)?[.Constants.__call] {
                    switch meta {
                        case .function(let fn):
                            return try await call(function: fn, at: idx, args: args, returns: returns, state: state, tailCall: tailCall)
                        default: break
                    }
                }
                throw Lua.error(in: state, message: "attempt to call a \(self.stack[idx].type) value")
        }
    }

    internal static func arith(op: LuaOpcode.Operation, _ a: LuaValue, _ b: LuaValue, state: LuaThread) async throws -> LuaValue {
        let an = a.toNumber
        let bn = b.toNumber
        if let an = an, let bn = bn {
            switch op {
                case .ADD: return .number(an + bn)
                case .SUB: return .number(an - bn)
                case .MUL: return .number(an * bn)
                case .DIV: return .number(an / bn)
                case .MOD:
                    let q = fmod(an, bn)
                    if (an < 0) != (bn < 0) {return .number(q + bn)}
                    return .number(q)
                case .POW: return .number(pow(an, bn))
                default: throw Lua.LuaError.vmError
            }
        }
        if let mt = a.metatable(in: state.luaState)?[.Constants.arithops[op]!].optional ?? b.metatable(in: state.luaState)?[.Constants.arithops[op]!].optional {
            switch mt {
                case .function(let fn):
                    let res = try await fn.call(in: state, with: [a, b])
                    return res.first ?? .nil
                default: throw Lua.error(in: state, message: "attempt to call a \(mt.type) value")
            }
        }
        if an != nil {
            throw Lua.error(in: state, message: "attempt to perform arithmetic on a \(b.type) value")
        } else {
            throw Lua.error(in: state, message: "attempt to perform arithmetic on a \(a.type) value")
        }
    }

    private static func concat(left: LuaValue, right: LuaValue, in state: LuaThread) async throws -> LuaValue {
        if case let .string(ls) = left {
            if case let .string(rs) = right {
                return .string(.rope(ls, rs))
            } else if case .number = right {
                return .string(.rope(ls, .string(right.toString)))
            }
        } else if case .number = left {
            if case let .string(rs) = right {
                return .string(.rope(.string(left.toString), rs))
            } else if case .number = right {
                return .string(.rope(.string(left.toString), .string(right.toString)))
            }
        }
        if let mt = left.metatable(in: state.luaState)?[.Constants.__concat].optional ?? right.metatable(in: state.luaState)?[.Constants.__concat].optional {
            switch mt {
                case .function(let fn):
                    let res = try await fn.call(in: state, with: [left, right])
                    return res.first ?? .nil
                default: throw Lua.error(in: state, message: "attempt to call a \(mt.type) value")
            }
        }
        throw Lua.error(in: state, message: "attempt to concatenate a \(left.type == "string" || left.type == "number" ? right.type : left.type) value")
    }

    internal static func concat(strings: ArraySlice<LuaValue>, in state: LuaThread) async throws -> LuaValue {
        switch strings.count {
            case 1: return strings.first!
            case 2: return try await concat(left: strings.first!, right: strings[strings.index(after: strings.startIndex)], in: state)
            //default: return try await concat(left: concat(strings: strings[strings.startIndex..<strings.startIndex.advanced(by: strings.count/2)], in: state), right: concat(strings: strings[strings.startIndex.advanced(by: strings.count/2)...], in: state), in: state)
            default: return try await concat(left: strings.first!, right: concat(strings: strings[strings.index(after: strings.startIndex)...], in: state), in: state)
        }
    }
}