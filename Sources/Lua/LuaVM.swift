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

    internal func prepare(args: [LuaValue], newargs: [LuaValue], closure: LuaClosure) {
        stack.replaceSubrange(0..<Int(closure.proto.numParams), with: newargs)
        if closure.proto.isVararg != 0 {
            if args.count > closure.proto.numParams {
                vararg = [LuaValue](args[Int(closure.proto.numParams)...])
            } else {
                vararg = []
            }
        }
        if stack.count < closure.proto.stackSize {
            stack.append(contentsOf: [LuaValue](repeating: .nil, count: Int(closure.proto.stackSize) - stack.count))
        }
    }

    internal func execute(at pc: inout Int, in state: LuaThread, nexec: inout Int) async throws -> ([LuaValue]?, CallInfo?) {
        if case let .lua(cl) = function {
            //print("Entering function \(cl) [\(nexec)]")
            let insts = cl.proto.opcodes
            let constants = cl.proto.constants
            oploop: while true {
                try await state.processHooks(at: pc, in: cl, savedpc: savedpc)
                let inst = insts[pc]
                savedpc = pc
                //print(cl.proto.lineinfo[pc], pc + 1, inst)
                pc += 1
                switch inst {
                    case .iABC(let op, let a, var b, let c):
                        //print(op, a, b, c)
                        lazy var rkb = (b & 0x100) != 0 ? constants[b & 0xFF] : stack[b]
                        lazy var rkc = (c & 0x100) != 0 ? constants[c & 0xFF] : stack[c]
                        switch op {
                            case .MOVE:
                                stack[a] = stack[b]
                            case .LOADKX:
                                let extraarg = insts[pc]
                                pc += 1
                                guard case let .iAx(op2, ax) = extraarg else {
                                    throw Lua.LuaError.vmError
                                }
                                if op2 != .EXTRAARG {
                                    throw Lua.LuaError.vmError
                                }
                                stack[a] = constants[ax]
                            case .LOADBOOL:
                                stack[a] = .boolean(b != 0)
                                if c != 0 {pc += 1}
                            case .LOADNIL:
                                for i in Int(a)...Int(a)+Int(b) {
                                    stack[i] = .nil
                                }
                            case .GETUPVAL:
                                stack[a] = await cl.upvalues[b].value
                            case .GETTABUP:
                                if b >= cl.upvalues.count {
                                    throw await Lua.error(in: state, message: "attempt to index upvalue '?' (a nil value)")
                                }
                                stack[a] = try await cl.upvalues[b].value.index(rkc, in: state)
                            case .GETTABLE:
                                stack[a] = try await stack[b].index(rkc, in: state)
                            case .SETUPVAL:
                                await cl.upvalues[b].set(value: stack[a])
                            case .SETTABUP:
                                if a >= cl.upvalues.count {
                                    throw await Lua.error(in: state, message: "attempt to index upvalue '?' (a nil value)")
                                }
                                try await cl.upvalues[a].value.index(rkb, value: rkc, in: state)
                            case .SETTABLE:
                                try await stack[a].index(rkb, value: rkc, in: state)
                            case .NEWTABLE:
                                let arrsz = (b >> 3) == 0 ? b & 7 : (8 | (b & 7)) << ((b >> 3) - 1)
                                let tabsz = (c >> 3) == 0 ? c & 7 : (8 | (c & 7)) << ((c >> 3) - 1)
                                stack[a] = .table(LuaTable(hash: Int(tabsz), array: Int(arrsz), state: state.luaState))
                            case .SELF:
                                stack[a+1] = stack[b]
                                stack[a] = try await stack[b].index(rkc, in: state)
                            case .ADD, .SUB, .MUL, .DIV, .MOD, .POW:
                                stack[a] = try await LuaVM.arith(op: op, rkb, rkc, state: state)
                            case .UNM:
                                if let n = stack[b].toNumber {
                                    stack[a] = .number(-n)
                                } else if let mt = await stack[b].metatable(in: state.luaState)?.metatable?[.Constants.__unm].optional {
                                    switch mt {
                                        case .function(let fn):
                                            let res = try await fn.call(in: state, with: [stack[b]])
                                            stack[a] = res.first ?? .nil
                                        default: throw await Lua.error(in: state, message: "attempt to perform arithmetic on a \(stack[b].type) value")
                                    }
                                } else {
                                    throw await Lua.error(in: state, message: "attempt to perform arithmetic on a \(stack[b].type) value")
                                }
                            case .NOT:
                                stack[a] = .boolean(!stack[b].toBool)
                            case .LEN:
                                switch stack[b] {
                                    case .string(let s): stack[a] = .number(Double(s.string.count))
                                    default:
                                        if let mt = await stack[b].metatable(in: state.luaState)?.metatable?[.Constants.__len] {
                                            switch mt {
                                                case .function(let fn):
                                                    let res = try await fn.call(in: state, with: [stack[b]])
                                                    stack[a] = res.first ?? .nil
                                                default: throw await Lua.error(in: state, message: "attempt to perform arithmetic on a \(stack[b].type) value")
                                            }
                                        } else if case let .table(tbl) = stack[b] {
                                            stack[a] = .number(Double(await tbl.count))
                                        } else {
                                            throw await Lua.error(in: state, message: "attempt to get length of a \(stack[b].type) value")
                                        }
                                }
                            case .CONCAT:
                                stack[a] = try await LuaVM.concat(strings: stack[Int(b)...Int(c)], in: state)
                            case .EQ:
                                let res: Bool
                                if rkb == rkc {
                                    res = true
                                } else if rkb.type == rkc.type,
                                    let mt = await rkb.metatable(in: state.luaState)?[.Constants.__eq],
                                    let mt2 = await rkc.metatable(in: state.luaState)?[.Constants.__eq],
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
                                } else if let mt = await rkb.metatable(in: state.luaState)?[.Constants.__lt], case let .function(fn) = mt {
                                    let v = try await fn.call(in: state, with: [rkb, rkc])
                                    res = v.first?.toBool ?? false
                                } else if let mt = await rkc.metatable(in: state.luaState)?[.Constants.__lt], case let .function(fn) = mt {
                                    let v = try await fn.call(in: state, with: [rkb, rkc])
                                    res = v.first?.toBool ?? false
                                } else if case .number = rkb {
                                    throw await Lua.error(in: state, message: "attempt to compare a \(rkc.type) value")
                                } else {
                                    throw await Lua.error(in: state, message: "attempt to compare a \(rkb.type) value")
                                }
                                if res != (a != 0) {pc += 1}
                            case .LE:
                                let res: Bool
                                if case let .number(nb) = rkb, case let .number(nc) = rkc {
                                    res = nb <= nc
                                } else if case let .string(sb) = rkb, case let .string(sc) = rkc {
                                    res = sb <= sc
                                } else if let mt = await rkb.metatable(in: state.luaState)?[.Constants.__le], case let .function(fn) = mt {
                                    let v = try await fn.call(in: state, with: [rkb, rkc])
                                    res = v.first?.toBool ?? false
                                } else if let mt = await rkc.metatable(in: state.luaState)?[.Constants.__le], case let .function(fn) = mt {
                                    let v = try await fn.call(in: state, with: [rkb, rkc])
                                    res = v.first?.toBool ?? false
                                } else if let mt = await rkb.metatable(in: state.luaState)?[.Constants.__lt], case let .function(fn) = mt {
                                    let v = try await fn.call(in: state, with: [rkc, rkb])
                                    res = !(v.first?.toBool ?? false)
                                } else if let mt = await rkc.metatable(in: state.luaState)?[.Constants.__lt], case let .function(fn) = mt {
                                    let v = try await fn.call(in: state, with: [rkc, rkb])
                                    res = !(v.first?.toBool ?? false)
                                } else if case .number = rkb {
                                    throw await Lua.error(in: state, message: "attempt to compare a \(rkc.type) value")
                                } else {
                                    throw await Lua.error(in: state, message: "attempt to compare a \(rkb.type) value")
                                }
                                if res != (a != 0) {pc += 1}
                            case .TEST:
                                if !(stack[a].toBool == (c != 0)) {pc += 1}
                            case .TESTSET:
                                if stack[b].toBool == (c != 0) {
                                    stack[a] = stack[b]
                                } else {
                                    pc += 1
                                }
                            case .CALL:
                                if let newci = try await call(at: Int(a), args: b == 0 ? nil : Int(b - 1), returns: c == 0 ? nil : Int(c - 1), state: state, tailCall: false) {
                                    savedpc = pc
                                    pc = 0
                                    nexec += 1
                                    return (nil, newci)
                                }
                            case .TAILCALL:
                                await state.popStack()
                                if let newci = try await call(at: Int(a), args: b == 0 ? nil : Int(b - 1), returns: numResults, state: state, tailCall: true) {
                                    tailcalls += 1
                                    pc = 0
                                    return (nil, newci)
                                } else {
                                    await state.pushDummy(self) // immediately removed
                                    b = UInt16(numResults != nil ? numResults! + 1 : 0)
                                    fallthrough
                                }
                            case .RETURN:
                                try await state.processHooksForReturn()
                                await state.popStack()
                                var res: [LuaValue]
                                if b == 0 {
                                    res = [LuaValue](stack[Int(a)..<top])
                                } else {
                                    res = [LuaValue](stack[Int(a)..<Int(a)+Int(b-1)])
                                }
                                nexec -= 1
                                if await state.stackIsEmpty() || nexec == 0 {
                                    //print("Results:", res)
                                    return (res, nil)
                                }
                                let stackTop = await state.top()
                                if let newpc = await stackTop.doReturn(with: &res) {
                                    pc = newpc
                                    return (nil, stackTop)
                                } else {
                                    return (res, nil)
                                }
                            case .TFORCALL:
                                let fn: LuaFunction
                                switch stack[a] {
                                    case .function(let _fn): fn = _fn
                                    default:
                                        guard let mt = await stack[a].metatable(in: state.luaState)?[.Constants.__call] else {throw await Lua.error(in: state, message: "attempt to call a \(stack[a].type) value")}
                                        guard case let .function(_fn) = mt else {throw await Lua.error(in: state, message: "attempt to call a \(stack[a].type) value")}
                                        fn = _fn
                                }
                                var res = try await fn.call(in: state, with: [stack[a+1], stack[a+2]])
                                if res.count < c {res.append(contentsOf: [LuaValue](repeating: .nil, count: Int(c) - res.count))}
                                else if res.count > c {res = [LuaValue](res[0..<Int(c)])}
                                stack.replaceSubrange((Int(a) + 3) ... (Int(a) + 2 + Int(c)), with: res)
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
                                guard case let .table(tbl) = stack[a] else {throw Lua.LuaError.vmError}
                                let _b: Int
                                if b == 0 {
                                    _b = top - Int(a) - 1
                                } else {
                                    _b = Int(b)
                                }
                                for j in 0..<_b {
                                    await tbl.set(index: Int(offset + j + 1), value: stack[Int(a) + Int(j) + 1])
                                }
                            case .VARARG:
                                if b == 0 {
                                    if let vararg = vararg {
                                        stack = [LuaValue](stack[0..<Int(a)])
                                        stack.append(contentsOf: vararg)
                                        top = stack.count
                                        if stack.count < cl.proto.stackSize {
                                            stack.append(contentsOf: [LuaValue](repeating: .nil, count: Int(cl.proto.stackSize) - stack.count))
                                        }
                                    } else {
                                        top = Int(a)
                                    }
                                } else if let vararg = vararg {
                                    for i in 0..<(Int(b) - 1) {
                                        stack[Int(a) + i] = i < vararg.count ? vararg[i] : .nil
                                    }
                                } else {
                                    for i in 0..<(Int(b) - 1) {
                                        stack[Int(a) + i] = .nil
                                    }
                                }
                            default: throw Lua.LuaError.vmError
                        }
                    case .iABx(let op, let a, let bx):
                        //print(op, a, bx)
                        switch op {
                            case .LOADK:
                                stack[a] = constants[bx]
                            case .CLOSURE:
                                let proto = cl.proto.prototypes[bx]
                                var upvalues = [LuaUpvalue]()
                                for upval in proto.upvalues {
                                    if upval.0 != 0 {
                                        if let uv = openUpvalues[Int(upval.1)] {
                                            upvalues.append(uv)
                                        } else {
                                            let uv = LuaUpvalue(in: self, at: Int(upval.1))
                                            upvalues.append(uv)
                                            openUpvalues[Int(upval.1)] = uv
                                        }
                                    } else {
                                        upvalues.append(cl.upvalues[upval.1])
                                    }
                                }
                                stack[a] = .function(.lua(LuaClosure(for: proto, with: upvalues)))
                            default: throw Lua.LuaError.vmError
                        }
                    case .iAsBx(let op, let a, let sbx):
                        //print(op, a, sbx)
                        switch op {
                            case .JMP:
                                pc += Int(sbx)
                                if a > 0 {
                                    for j in (Int(a) - 1) ..< stack.count {
                                        if let uv = openUpvalues[j] {
                                            await uv.close()
                                            openUpvalues[j] = nil
                                        }
                                    }
                                }
                            case .FORPREP:
                                guard case let .number(initial) = stack[a] else {throw await Lua.error(in: state, message: "'for' initial value must be a number")}
                                guard case .number = stack[a + 1] else {throw await Lua.error(in: state, message: "'for' initial value must be a number")}
                                guard case let .number(step) = stack[a + 2] else {throw await Lua.error(in: state, message: "'for' initial value must be a number")}
                                stack[a] = .number(initial - step)
                                pc += Int(sbx)
                            case .FORLOOP:
                                guard case var .number(value) = stack[a] else {throw await Lua.error(in: state, message: "'for' initial value must be a number")}
                                guard case let .number(limit) = stack[a + 1] else {throw await Lua.error(in: state, message: "'for' initial value must be a number")}
                                guard case let .number(step) = stack[a + 2] else {throw await Lua.error(in: state, message: "'for' initial value must be a number")}
                                value += step
                                stack[a] = .number(value)
                                if step > 0 ? value <= limit : value >= limit {
                                    stack[a + 3] = .number(value)
                                    pc += Int(sbx)
                                }
                            case .TFORLOOP:
                                if stack[a + 1] != .nil {
                                    stack[a] = stack[a + 1]
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

    private func call(function fn: LuaFunction, at idx: Int, args: Int?, returns: Int?, state: LuaThread, tailCall: Bool) async throws -> CallInfo? {
        switch fn {
            case .lua(let cl):
                let nextci = CallInfo(for: fn, numResults: returns, stackSize: Int(cl.proto.stackSize))
                var argv = args != nil ? (args == 0 ? [] : [LuaValue](stack[(idx + 1) ... (idx + args!)])) : [LuaValue](stack[(idx+1)..<top])
                if argv.count > cl.proto.numParams {
                    if cl.proto.isVararg != 0 {
                        await nextci.setupVarargs(with: [LuaValue](argv[Int(cl.proto.numParams)...]))
                    }
                    argv = [LuaValue](argv[0..<Int(cl.proto.numParams)])
                } else if argv.count < cl.proto.numParams {
                    argv.append(contentsOf: [LuaValue](repeating: .nil, count: Int(cl.proto.numParams) - argv.count))
                }
                if cl.proto.isVararg != 0 {
                    await nextci.finishVarargs()
                }
                //print("Arguments:", argv, nextci.vararg)
                await nextci.set(args: argv, count: cl.proto.numParams)
                top = idx
                if returns == nil {
                    stack = [LuaValue](stack[0..<idx])
                }
                try await state.prepareCall(for: nextci, tailCall: tailCall)
                return nextci
            case .swift(let sfn):
                var res = try await state.call(swift: sfn, function: fn, in: self, at: idx, args: args, returns: returns, tailCall: tailCall)
                //print("Results:", res)
                if let returns = returns {
                    if res.count > returns {res = [LuaValue](res[0..<returns])}
                    else if res.count < returns {res.append(contentsOf: [LuaValue](repeating: .nil, count: returns - res.count))}
                    stack.replaceSubrange(idx ..< min(idx + returns, stack.count), with: res)
                    top = min(idx + returns, stack.count)
                } else {
                    let oldsz = stack.count
                    stack = [LuaValue](stack[0..<idx])
                    stack.append(contentsOf: res)
                    if stack.count < oldsz {
                        stack.append(contentsOf: [LuaValue](repeating: .nil, count: oldsz - stack.count))
                    }
                    top = idx + res.count
                }
                await state.popStack()
                return nil
        }
    }

    internal func call(at idx: Int, args: Int?, returns: Int?, state: LuaThread, tailCall: Bool = false) async throws -> CallInfo? {
        switch stack[idx] {
            case .function(let fn):
                return try await call(function: fn, at: idx, args: args, returns: returns, state: state, tailCall: tailCall)
            default:
                if let meta = await stack[idx].metatable(in: state.luaState)?[.Constants.__call] {
                    switch meta {
                        case .function(let fn):
                            return try await call(function: fn, at: idx, args: args, returns: returns, state: state, tailCall: tailCall)
                        default: break
                    }
                }
                throw await Lua.error(in: state, message: "attempt to call a \(stack[idx].type) value")
        }
    }

    private func doReturn(with res: inout [LuaValue]) -> Int? {
        switch function {
            case .lua(let newcl):
                if let numResults = numResults {
                    if res.count < numResults {res.append(contentsOf: [LuaValue](repeating: .nil, count: numResults - res.count))}
                    else if res.count > numResults {res = [LuaValue](res[0..<numResults])}
                    stack.replaceSubrange(top..<(top + res.count), with: res)
                } else {
                    stack.append(contentsOf: res)
                    if stack.count < newcl.proto.stackSize {
                        stack.append(contentsOf: [LuaValue](repeating: .nil, count: Int(newcl.proto.stackSize) - stack.count))
                    }
                }
                //print("Results:", res)
                top += res.count
                return savedpc
            case .swift:
                return nil
        }
    }

    private func setupVarargs(with args: [LuaValue]) {
        vararg = args
    }

    private func finishVarargs() {
        if vararg == nil {
            vararg = [LuaValue]()
        }
    }

    private func set(args: [LuaValue], count: UInt8) {
        stack.replaceSubrange(0..<Int(count), with: args)
    }

    internal var location: String? {
        if case let .lua(cl) = function, savedpc < cl.proto.lineinfo.count {
            return "\(Lua.shortSource(for: cl)):\(cl.proto.lineinfo[savedpc]): "
        }
        return nil
    }

    public func local(_ index: Int) throws -> (String, LuaValue)? {
        if index < 0, let vararg = vararg {
            if -index >= vararg.count {
                return nil
            }
            return ("(*vararg)", vararg[-index - 1])
        } else if index > 0 {
            if index > stack.count {
                return nil
            }
            var name = "(*temporary)"
            if case let .lua(cl) = function, index <= cl.proto.locals.count {
                name = cl.proto.locals[index-1].0
            }
            return (name, stack[index-1])
        } else {
            return nil
        }
    }

    public func local(_ index: Int, value: LuaValue) throws -> String? {
        if index < 0 && vararg != nil {
            if -index >= vararg!.count {
                return nil
            }
            vararg![-index - 1] = value
            return "(*vararg)"
        } else if index > 0 {
            if index > stack.count {
                return nil
            }
            stack[index-1] = value
            var name = "(*temporary)"
            if case let .lua(cl) = function, index <= cl.proto.locals.count {
                name = cl.proto.locals[index-1].0
            }
            return name
        } else {
            throw Lua.LuaError.internalError
        }
    }

    internal func get(args: Int?, at idx: Int) -> [LuaValue] {
        return args != nil ? (args == 0 ? [] : [LuaValue](stack[(idx + 1) ... (idx + args!)])) : [LuaValue](stack[(idx+1)..<top])
    }

    internal func getfuncname() -> (String, Lua.Debug.NameType)? {
        guard case let .lua(cl) = function else {return nil}
        let p = cl.proto
        let pc = savedpc - 1
        let i = p.opcodes[pc == -1 ? 0 : pc]
        switch i {
            case .iABC(let op, let a, _, _):
                switch op {
                    case .CALL, .TAILCALL:
                        return LuaThread.getobjname(p, pc, a)
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

    internal func set(at index: Int, value: LuaValue) {
        stack[index] = value
    }
}

internal struct LuaVM {
    internal static func execute(closure: LuaClosure, with args: [LuaValue], numResults: Int?, state: LuaThread) async throws -> [LuaValue] {
        //print("Starting interpreter with args", args)
        var ci = CallInfo(for: .lua(closure), numResults: numResults, stackSize: Int(closure.proto.stackSize))
        var newargs = args
        if newargs.count < closure.proto.numParams {
            newargs.append(contentsOf: [LuaValue](repeating: .nil, count: Int(closure.proto.numParams) - args.count))
        } else if newargs.count > closure.proto.numParams {
            newargs = [LuaValue](newargs[0..<Int(closure.proto.numParams)])
        }
        await ci.prepare(args: args, newargs: newargs, closure: closure)
        try await state.prepareCall(for: ci)
        var nexec = 1
        var pc = 0
        while true {
            let (res, newci) = try await ci.execute(at: &pc, in: state, nexec: &nexec)
            if let res = res {
                return res
            } else if let newci = newci {
                ci = newci
            }
        }
    }

    internal static func call(in ci: CallInfo, at idx: Int, args: Int?, returns: Int?, state: LuaThread, tailCall: Bool = false) async throws -> CallInfo? {
        return try await ci.call(at: idx, args: args, returns: returns, state: state, tailCall: tailCall)
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
        if let mt = await a.metatable(in: state.luaState)?[.Constants.arithops[op]!].optional {
            switch mt {
                case .function(let fn):
                    let res = try await fn.call(in: state, with: [a, b])
                    return res.first ?? .nil
                default: throw await Lua.error(in: state, message: "attempt to call a \(mt.type) value")
            }
        } else if let mt = await b.metatable(in: state.luaState)?[.Constants.arithops[op]!].optional {
            switch mt {
                case .function(let fn):
                    let res = try await fn.call(in: state, with: [a, b])
                    return res.first ?? .nil
                default: throw await Lua.error(in: state, message: "attempt to call a \(mt.type) value")
            }
        }
        if an != nil {
            throw await Lua.error(in: state, message: "attempt to perform arithmetic on a \(b.type) value")
        } else {
            throw await Lua.error(in: state, message: "attempt to perform arithmetic on a \(a.type) value")
        }
    }

    private static func concat(left: LuaValue, right: LuaValue, in state: LuaThread) async throws -> LuaValue {
        if case let .string(ls) = left {
            if case let .string(rs) = right {
                return .string(.rope(ls, rs))
            } else if case .number = right {
                return .string(.rope(ls, .string(await right.toString)))
            }
        } else if case .number = left {
            if case let .string(rs) = right {
                return .string(.rope(.string(await left.toString), rs))
            } else if case .number = right {
                return .string(.rope(.string(await left.toString), .string(await right.toString)))
            }
        }
        if let mt = await left.metatable(in: state.luaState)?[.Constants.__concat].optional {
            switch mt {
                case .function(let fn):
                    let res = try await fn.call(in: state, with: [left, right])
                    return res.first ?? .nil
                default: throw await Lua.error(in: state, message: "attempt to call a \(mt.type) value")
            }
        } else if let mt = await right.metatable(in: state.luaState)?[.Constants.__concat].optional {
            switch mt {
                case .function(let fn):
                    let res = try await fn.call(in: state, with: [left, right])
                    return res.first ?? .nil
                default: throw await Lua.error(in: state, message: "attempt to call a \(mt.type) value")
            }
        }
        throw await Lua.error(in: state, message: "attempt to concatenate a \(left.type == "string" || left.type == "number" ? right.type : left.type) value")
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