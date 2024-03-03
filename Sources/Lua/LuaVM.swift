import Math

extension Array {
    subscript(index: UInt8) -> Array.Element {get {return self[Int(index)]} set (value) {self[Int(index)] = value}}
    subscript(index: UInt16) -> Array.Element {get {return self[Int(index)]} set (value) {self[Int(index)] = value}}
    subscript(index: UInt32) -> Array.Element {get {return self[Int(index)]} set (value) {self[Int(index)] = value}}
}

internal class LuaVM {
    internal static func execute(closure: LuaClosure, with args: [LuaValue], numResults: Int, state: LuaThread) async throws -> [LuaValue] {
        //print("Starting interpreter with args", args)
        var ci = CallInfo(for: .lua(closure), numResults: numResults, stackSize: Int(closure.proto.stackSize))
        var newargs = args
        if newargs.count < closure.proto.numParams {
            newargs.append(contentsOf: [LuaValue](repeating: .nil, count: Int(closure.proto.numParams) - args.count))
        } else if newargs.count > closure.proto.numParams {
            newargs = [LuaValue](newargs[0..<Int(closure.proto.numParams)])
        }
        ci.stack.replaceSubrange(0..<Int(closure.proto.numParams), with: newargs)
        if closure.proto.isVararg != 0 {
            if args.count > closure.proto.numParams {
                ci.vararg = [LuaValue](args[Int(closure.proto.numParams)...])
            } else {
                ci.vararg = []
            }
        }
        state.callStack.append(ci)
        var nexec = 1
        var pc = 0
        while true {
            if case let .lua(cl) = ci.function {
                //print("Entering function \(cl) [\(nexec)]")
                let insts = cl.proto.opcodes
                let constants = cl.proto.constants
                oploop: while true {
                    if !state.luaState.tablesToBeFinalized.isEmpty {
                        for t in state.luaState.tablesToBeFinalized {
                            if let mt = t.metatable, case let .function(gc) = mt["__gc"] {
                                _ = try await gc.call(in: state, with: [.table(t)])
                            }
                        }
                        state.luaState.tablesToBeFinalized = []
                    }
                    let inst = insts[pc]
                    ci.savedpc = pc
                    //print(cl.proto.lineinfo[pc], pc + 1, inst)
                    pc += 1
                    switch inst {
                        case .iABC(let op, let a, var b, let c):
                            //print(op, a, b, c)
                            lazy var rkb = (b & 0x100) != 0 ? constants[b & 0xFF] : ci.stack[b]
                            lazy var rkc = (c & 0x100) != 0 ? constants[c & 0xFF] : ci.stack[c]
                            switch op {
                                case .MOVE:
                                    ci.stack[a] = ci.stack[b]
                                case .LOADKX:
                                    let extraarg = insts[pc]
                                    pc += 1
                                    guard case let .iAx(op2, ax) = extraarg else {
                                        throw Lua.LuaError.vmError
                                    }
                                    if op2 != .EXTRAARG {
                                        throw Lua.LuaError.vmError
                                    }
                                    ci.stack[a] = constants[ax]
                                case .LOADBOOL:
                                    ci.stack[a] = .boolean(b != 0)
                                    if c != 0 {pc += 1}
                                case .LOADNIL:
                                    for i in Int(a)...Int(a)+Int(b) {
                                        ci.stack[i] = .nil
                                    }
                                case .GETUPVAL:
                                    ci.stack[a] = cl.upvalues[b].value
                                case .GETTABUP:
                                    if b >= cl.upvalues.count {
                                        throw Lua.error(in: state, message: "attempt to index upvalue '?' (a nil value)")
                                    }
                                    ci.stack[a] = try await cl.upvalues[b].value.index(rkc, in: state)
                                case .GETTABLE:
                                    ci.stack[a] = try await ci.stack[b].index(rkc, in: state)
                                case .SETUPVAL:
                                    cl.upvalues[b].value = ci.stack[a]
                                case .SETTABUP:
                                    if a >= cl.upvalues.count {
                                        throw Lua.error(in: state, message: "attempt to index upvalue '?' (a nil value)")
                                    }
                                    try await cl.upvalues[a].value.index(rkb, value: rkc, in: state)
                                case .SETTABLE:
                                    try await ci.stack[a].index(rkb, value: rkc, in: state)
                                case .NEWTABLE:
                                    let arrsz = (b >> 3) == 0 ? b & 7 : (8 | (b & 7)) << ((b >> 3) - 1)
                                    let tabsz = (c >> 3) == 0 ? c & 7 : (8 | (c & 7)) << ((c >> 3) - 1)
                                    ci.stack[a] = .table(LuaTable(hash: Int(tabsz), array: Int(arrsz), state: state.luaState))
                                case .SELF:
                                    ci.stack[a+1] = ci.stack[b]
                                    ci.stack[a] = try await ci.stack[b].index(rkc, in: state)
                                case .ADD, .SUB, .MUL, .DIV, .MOD, .POW:
                                    ci.stack[a] = try await arith(op: op, rkb, rkc, state: state)
                                case .UNM:
                                    switch ci.stack[b] {
                                        case .number(let n): ci.stack[a] = .number(-n)
                                        case .string(let s):
                                            if let n = Double(s.string) {
                                                ci.stack[a] = .number(-n)
                                            } else {
                                                fallthrough
                                            }
                                        default:
                                            if let mt = ci.stack[b].metatable(in: state.luaState)?.metatable?[.Constants.__unm] {
                                                switch mt {
                                                    case .function(let fn):
                                                        let res = try await fn.call(in: state, with: [ci.stack[b]])
                                                        ci.stack[a] = res.first ?? .nil
                                                    default: throw Lua.error(in: state, message: "attempt to perform arithmetic on a \(ci.stack[b].type) value")
                                                }
                                            } else {
                                                throw Lua.error(in: state, message: "attempt to perform arithmetic on a \(ci.stack[b].type) value")
                                            }
                                    }
                                case .NOT:
                                    ci.stack[a] = .boolean(!ci.stack[b].toBool)
                                case .LEN:
                                    switch ci.stack[b] {
                                        case .string(let s): ci.stack[a] = .number(Double(s.string.count))
                                        default:
                                            if let mt = ci.stack[b].metatable(in: state.luaState)?.metatable?[.Constants.__len] {
                                                switch mt {
                                                    case .function(let fn):
                                                        let res = try await fn.call(in: state, with: [ci.stack[b]])
                                                        ci.stack[a] = res.first ?? .nil
                                                    default: throw Lua.error(in: state, message: "attempt to perform arithmetic on a \(ci.stack[b].type) value")
                                                }
                                            } else if case let .table(tbl) = ci.stack[b] {
                                                ci.stack[a] = .number(Double(tbl.count))
                                            } else {
                                                throw Lua.error(in: state, message: "attempt to get length of a \(ci.stack[b].type) value")
                                            }
                                    }
                                case .CONCAT:
                                    ci.stack[a] = .string(concat(strings: ci.stack[Int(b)...Int(c)]))
                                case .EQ:
                                    if (rkb == rkc) != (a != 0) {pc += 1}
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
                                case .TEST:
                                    if !(ci.stack[a].toBool == (c != 0)) {pc += 1}
                                case .TESTSET:
                                    if ci.stack[b].toBool == (c != 0) {
                                        ci.stack[a] = ci.stack[b]
                                    } else {
                                        pc += 1
                                    }
                                case .CALL:
                                    if let newci = try await call(in: ci, at: Int(a), args: b == 0 ? nil : Int(b - 1), returns: c == 0 ? nil : Int(c - 1), state: state) {
                                        ci.savedpc = pc
                                        ci = newci
                                        pc = 0
                                        nexec += 1
                                        break oploop
                                    }
                                case .TAILCALL:
                                    _ = state.callStack.popLast()
                                    if let newci = try await call(in: ci, at: Int(a), args: b == 0 ? nil : Int(b - 1), returns: ci.numResults, state: state) {
                                        ci = newci
                                        pc = 0
                                        break oploop
                                    } else {
                                        state.callStack.append(ci) // immediately removed
                                        b = 0
                                        fallthrough
                                    }
                                case .RETURN:
                                    _ = state.callStack.popLast()
                                    var res: [LuaValue]
                                    if b == 0 {
                                        res = [LuaValue](ci.stack[Int(a)..<ci.top])
                                    } else {
                                        res = [LuaValue](ci.stack[Int(a)..<Int(a)+Int(b-1)])
                                    }
                                    nexec -= 1
                                    if state.callStack.isEmpty || nexec == 0 {
                                        return res
                                    }
                                    switch state.callStack.last!.function {
                                        case .lua(let newcl):
                                            let newci = state.callStack.last!
                                            if let numResults = ci.numResults {
                                                if res.count < numResults {res.append(contentsOf: [LuaValue](repeating: .nil, count: numResults - res.count))}
                                                else if res.count > numResults {res = [LuaValue](res[0..<numResults])}
                                                newci.stack.replaceSubrange(newci.top..<(newci.top + res.count), with: res)
                                            } else {
                                                newci.stack.append(contentsOf: res)
                                                if newci.stack.count < newcl.proto.stackSize {
                                                    newci.stack.append(contentsOf: [LuaValue](repeating: .nil, count: Int(newcl.proto.stackSize) - newci.stack.count))
                                                }
                                            }
                                            //print("Results:", res)
                                            newci.top += res.count
                                            ci = newci
                                            pc = ci.savedpc
                                            break oploop
                                        case .swift:
                                            return res
                                    }
                                case .TFORCALL:
                                    let fn: LuaFunction
                                    switch ci.stack[a] {
                                        case .function(let _fn): fn = _fn
                                        default:
                                            guard let mt = ci.stack[a].metatable(in: state.luaState)?[.Constants.__call] else {throw Lua.error(in: state, message: "attempt to call a \(ci.stack[a].type) value")}
                                            guard case let .function(_fn) = mt else {throw Lua.error(in: state, message: "attempt to call a \(ci.stack[a].type) value")}
                                            fn = _fn
                                    }
                                    var res = try await fn.call(in: state, with: [ci.stack[a+1], ci.stack[a+2]])
                                    if res.count < c {res.append(contentsOf: [LuaValue](repeating: .nil, count: Int(c) - res.count))}
                                    else if res.count > c {res = [LuaValue](res[0..<Int(c)])}
                                    ci.stack.replaceSubrange((Int(a) + 3) ... (Int(a) + 2 + Int(c)), with: res)
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
                                    guard case let .table(tbl) = ci.stack[a] else {throw Lua.LuaError.vmError}
                                    let _b: Int
                                    if b == 0 {
                                        _b = ci.top - Int(a) - 1
                                    } else {
                                        _b = Int(b)
                                    }
                                    for j in 0..<_b {
                                        tbl[Int(offset + j + 1)] = ci.stack[Int(a) + Int(j) + 1]
                                    }
                                case .VARARG:
                                    if b == 0 {
                                        if let vararg = ci.vararg {
                                            ci.stack = [LuaValue](ci.stack[0..<Int(a)])
                                            ci.stack.append(contentsOf: vararg)
                                            ci.top = ci.stack.count
                                            if ci.stack.count < cl.proto.stackSize {
                                                ci.stack.append(contentsOf: [LuaValue](repeating: .nil, count: Int(cl.proto.stackSize) - ci.stack.count))
                                            }
                                        } else {
                                            ci.top = Int(a)
                                        }
                                    } else if let vararg = ci.vararg {
                                        for i in 0..<(Int(b) - 1) {
                                            ci.stack[Int(a) + i] = i < vararg.count ? vararg[i] : .nil
                                        }
                                    } else {
                                        for i in 0..<(Int(b) - 1) {
                                            ci.stack[Int(a) + i] = .nil
                                        }
                                    }
                                default: throw Lua.LuaError.vmError
                            }
                        case .iABx(let op, let a, let bx):
                            //print(op, a, bx)
                            switch op {
                                case .LOADK:
                                    ci.stack[a] = constants[bx]
                                case .CLOSURE:
                                    let proto = cl.proto.prototypes[bx]
                                    var upvalues = [LuaUpvalue]()
                                    for upval in proto.upvalues {
                                        if upval.0 != 0 {
                                            let uv = LuaUpvalue(in: ci, at: Int(upval.1))
                                            upvalues.append(uv)
                                            state.luaState.openUpvalues.append(uv)
                                        } else {
                                            upvalues.append(cl.upvalues[upval.1])
                                        }
                                    }
                                    ci.stack[a] = .function(.lua(LuaClosure(for: proto, with: upvalues, environment: cl.environment)))
                                default: throw Lua.LuaError.vmError
                            }
                        case .iAsBx(let op, let a, let sbx):
                            //print(op, a, sbx)
                            switch op {
                                case .JMP:
                                    pc += Int(sbx)
                                    if a > 0 {
                                        for j in (Int(a) - 1) ..< ci.top {
                                            state.luaState.openUpvalues = state.luaState.openUpvalues.filter({uv in
                                                if uv.in(stack: ci, at: j) {
                                                    uv.close()
                                                    return false
                                                }
                                                return true
                                            })
                                        }
                                    }
                                case .FORPREP:
                                    guard case let .number(initial) = ci.stack[a] else {throw Lua.error(in: state, message: "'for' initial value must be a number")}
                                    guard case .number = ci.stack[a + 1] else {throw Lua.error(in: state, message: "'for' initial value must be a number")}
                                    guard case let .number(step) = ci.stack[a + 2] else {throw Lua.error(in: state, message: "'for' initial value must be a number")}
                                    ci.stack[a] = .number(initial - step)
                                    pc += Int(sbx)
                                case .FORLOOP:
                                    guard case var .number(value) = ci.stack[a] else {throw Lua.error(in: state, message: "'for' initial value must be a number")}
                                    guard case let .number(limit) = ci.stack[a + 1] else {throw Lua.error(in: state, message: "'for' initial value must be a number")}
                                    guard case let .number(step) = ci.stack[a + 2] else {throw Lua.error(in: state, message: "'for' initial value must be a number")}
                                    value += step
                                    ci.stack[a] = .number(value)
                                    if step > 0 ? value <= limit : value >= limit {
                                        ci.stack[a + 3] = .number(value)
                                        pc += Int(sbx)
                                    }
                                case .TFORLOOP:
                                    if ci.stack[a + 1] != .nil {
                                        ci.stack[a] = ci.stack[a + 1]
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
    }

    private static func call(function fn: LuaFunction, in ci: CallInfo, at idx: Int, args: Int?, returns: Int?, state: LuaThread) async throws -> CallInfo? {
        switch fn {
            case .lua(let cl):
                let nextci = CallInfo(for: fn, numResults: returns, stackSize: Int(cl.proto.stackSize))
                var argv = args != nil ? (args == 0 ? [] : [LuaValue](ci.stack[(idx + 1) ... (idx + args!)])) : [LuaValue](ci.stack[(idx+1)..<ci.top])
                if argv.count > cl.proto.numParams {
                    if cl.proto.isVararg != 0 {
                        nextci.vararg = [LuaValue](argv[Int(cl.proto.numParams)...])
                    }
                    argv = [LuaValue](argv[0..<Int(cl.proto.numParams)])
                } else if argv.count < cl.proto.numParams {
                    argv.append(contentsOf: [LuaValue](repeating: .nil, count: Int(cl.proto.numParams) - argv.count))
                }
                if cl.proto.isVararg != 0 && nextci.vararg == nil {
                    nextci.vararg = [LuaValue]()
                }
                //print("Arguments:", argv, nextci.vararg)
                nextci.stack.replaceSubrange(0..<Int(cl.proto.numParams), with: argv)
                ci.top = idx
                if returns == nil {
                    ci.stack = [LuaValue](ci.stack[0..<idx])
                }
                state.callStack.append(nextci)
                return nextci
            case .swift(let sfn):
                state.callStack.append(CallInfo(for: fn, numResults: returns, stackSize: 0))
                let argv = args != nil ? (args == 0 ? [] : [LuaValue](ci.stack[(idx + 1) ... (idx + args!)])) : [LuaValue](ci.stack[(idx+1)..<ci.top])
                //print("Arguments:", argv)
                var res = try await sfn.body(Lua(in: state), LuaArgs(argv))
                //print("Results:", res)
                if let returns = returns {
                    if res.count > returns {res = [LuaValue](res[0..<returns])}
                    else if res.count < returns {res.append(contentsOf: [LuaValue](repeating: .nil, count: returns - res.count))}
                    ci.stack.replaceSubrange(idx ..< min(idx + returns, ci.stack.count), with: res)
                    ci.top = min(idx + returns, ci.stack.count)
                } else {
                    let oldsz = ci.stack.count
                    ci.stack = [LuaValue](ci.stack[0..<idx])
                    ci.stack.append(contentsOf: res)
                    if ci.stack.count < oldsz {
                        ci.stack.append(contentsOf: [LuaValue](repeating: .nil, count: oldsz - ci.stack.count))
                    }
                    ci.top = idx + res.count
                }
                state.callStack.removeLast()
                return nil
        }
    }

    internal static func call(in ci: CallInfo, at idx: Int, args: Int?, returns: Int?, state: LuaThread) async throws -> CallInfo? {
        switch ci.stack[idx] {
            case .function(let fn):
                return try await call(function: fn, in: ci, at: idx, args: args, returns: returns, state: state)
            default:
                if let meta = ci.stack[idx].metatable(in: state.luaState)?[.Constants.__call] {
                    switch meta {
                        case .function(let fn):
                            return try await call(function: fn, in: ci, at: idx, args: args, returns: returns, state: state)
                        default: break
                    }
                }
                throw Lua.error(in: state, message: "attempt to call a \(ci.stack[idx].type) value")
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
                case .MOD: return .number(an.truncatingRemainder(dividingBy: bn))
                case .POW: return .number(pow(an, bn))
                default: throw Lua.LuaError.vmError
            }
        }
        if let mt = a.metatable(in: state.luaState)?[.Constants.arithops[op]!] ?? b.metatable(in: state.luaState)?[.Constants.arithops[op]!] {
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

    internal static func concat(strings: ArraySlice<LuaValue>) -> LuaString {
        switch strings.count {
            case 1: return .string(strings.first!.toString)
            case 2: return .rope(.string(strings.first!.toString), .string(strings[strings.index(after: strings.startIndex)].toString))
            default: return .rope(concat(strings: strings[strings.startIndex..<strings.startIndex.advanced(by: strings.count/2)]), concat(strings: strings[strings.startIndex.advanced(by: strings.count/2)...]))
        }
    }
}