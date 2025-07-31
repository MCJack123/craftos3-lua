import Lua

internal class LuaCode {
    fileprivate enum VarType {
        case local
        case upvalue
        case global
        case globalLocal
    }

    fileprivate class LocalInfo {
        internal var name: String
        internal var startpc: Int
        internal var endpc: Int = -1
        internal var active = true
        internal init(_ name: String, _ startpc: Int) {
            self.name = name
            self.startpc = startpc
            self.endpc = startpc
        }
    }

    internal class Function {
        private let parent: Block?
        private var opcodes = [LuaOpcode]()
        private var constants = [LuaValue: Int]()
        private var nextConstant = 0
        private var prototypes = [Function]()
        private var upvalues = [String: (Int, Bool, Int)]() // index, in stack, stack index
        private var nextUpvalue = 0
        private var stackSize: UInt8 = 0
        private var numParams: UInt8 = 0
        private var isVararg: UInt8 = 0
        private var name: [UInt8] = ""
        private var lineDefined: Int32 = 0
        fileprivate var lastLineDefined: Int32 = 0
        private var lineinfo = [Int32]()
        fileprivate var localinfo = [LocalInfo]()
        private var labels = [String: Int]()
        private var openGotos = [(String, Int)]()
        internal var root: Block!
        internal var line: Int = 0
        private var closureLevel: Int? = nil

        fileprivate init(named name: [UInt8]) {
            self.parent = nil
            self.name = name
            root = Block(for: self)
            upvalues["_ENV"] = (0, true, 0)
            nextUpvalue = 1
            isVararg = 1
        }
        
        fileprivate init(from parent: Block, args: Int, vararg: Bool) {
            self.parent = parent
            self.name = parent.fn.name
            self.numParams = UInt8(args)
            self.stackSize = self.numParams
            self.isVararg = vararg ? 1 : 0
            self.lineDefined = Int32(parent.fn.line)
            root = Block(for: self)
        }

        fileprivate func add(opcode: LuaOpcode) -> Int {
            opcodes.append(opcode)
            lineinfo.append(Int32(line))
            return opcodes.count
        }

        fileprivate func add(prototype: Function) -> Int {
            prototypes.append(prototype)
            return prototypes.count - 1
        }

        private func checkLevels(name: String, label: Int, statement: Int) throws {
            for info in localinfo {
                if label > info.startpc && label <= info.endpc && (statement < info.startpc || (statement > info.endpc && !info.active)) {
                    throw LuaParser.Error.gotoError(message: "<goto \(name)> jumps into the scope of local '\(info.name)'")
                }
            }
        }

        fileprivate func add(label: String, in block: Block) throws {
            if labels[label] != nil {
                throw LuaParser.Error.gotoError(message: "label '\(label)' already defined")
            }
            labels[label] = top
            openGotos = try openGotos.filter {stat in
                if stat.0 == label {
                    try checkLevels(name: stat.0, label: top, statement: stat.1)
                    modify(at: stat.1, opcode: .iAsBx(.JMP, UInt8(block.level + 1), Int32(top - stat.1 - 1)))
                    return false
                }
                return true
            }
        }

        fileprivate func `goto`(_ label: String, in block: Block) throws {
            if let lb = labels[label] {
                try checkLevels(name: label, label: lb, statement: top)
                _ = add(opcode: .iAsBx(.JMP, UInt8(0), Int32(lb - top - 1)))
            } else {
                openGotos.append((label, add(opcode: .iAsBx(.JMP, 0, 0)) - 1))
            }
        }

        fileprivate func modify(at idx: Int, opcode: LuaOpcode) {
            opcodes[idx] = opcode
        }

        fileprivate var top: Int {return opcodes.count}
        fileprivate var hasOpenGotos: Bool {return !openGotos.isEmpty}

        fileprivate func allocate(slot idx: Int) {
            stackSize = max(stackSize, UInt8(idx + 1))
        }

        fileprivate func constant(for value: LuaValue) -> Int {
            if let k = constants[value] {
                return k
            } else {
                constants[value] = nextConstant
                nextConstant += 1
                return nextConstant - 1
            }
        }

        fileprivate func upvalue(named name: String) -> (VarType, Int) {
            if let uv = upvalues[name] {
                return (.upvalue, uv.0)
            } else if let parent = parent {
                let (type, idx) = parent.variable(named: name)
                switch type {
                    case .local:
                        upvalues[name] = (nextUpvalue, true, idx)
                        nextUpvalue += 1
                        parent.fn.closureLevel = min(parent.fn.closureLevel ?? 10000, idx)
                        return (.upvalue, nextUpvalue - 1)
                    case .upvalue:
                        upvalues[name] = (nextUpvalue, false, idx)
                        nextUpvalue += 1
                        return (.upvalue, nextUpvalue - 1)
                    case .global, .globalLocal:
                        if let env = upvalues["_ENV"] {
                            return (.global, env.0)
                        } else {
                            let (etype, eidx) = parent.variable(named: "_ENV")
                            switch etype {
                                case .local:
                                    upvalues["_ENV"] = (nextUpvalue, true, eidx)
                                    nextUpvalue += 1
                                    parent.fn.closureLevel = min(parent.fn.closureLevel ?? 10000, eidx)
                                    return (.global, nextUpvalue - 1)
                                case .upvalue:
                                    upvalues["_ENV"] = (nextUpvalue, false, eidx)
                                    nextUpvalue += 1
                                    return (.global, nextUpvalue - 1)
                                case .global:
                                    // this should never happen
                                    upvalues["_ENV"] = (nextUpvalue, false, idx)
                                    nextUpvalue += 1
                                    return (.global, nextUpvalue - 1)
                                case .globalLocal:
                                    // this should never happen
                                    upvalues["_ENV"] = (nextUpvalue, true, idx)
                                    nextUpvalue += 1
                                    return (.global, nextUpvalue - 1)
                            }
                        }
                }
            } else if let env = upvalues["_ENV"] {
                return (.global, env.0)
            } else {
                fatalError("Internal parser error: Global variable requested, but no environment was provided")
            }
        }

        internal func close(to level: Int) -> UInt8 {
            if let closureLevel = closureLevel {
                if level >= closureLevel {
                    self.closureLevel = min(closureLevel, level - 1)
                    return UInt8(level + 1)
                } else {
                    self.closureLevel = nil
                    return UInt8(closureLevel + 1)
                }
            } else {
                return 0
            }
        }

        internal func encode() -> LuaInterpretedFunction {
            return LuaInterpretedFunction(
                opcodes: opcodes,
                constants: constants.keys.sorted(by: {self.constants[$0]! < self.constants[$1]!}),
                prototypes: prototypes.map({$0.encode()}),
                upvalues: upvalues.map({($0.value.1 ? UInt8(1) : UInt8(0), UInt8($0.value.2), $0.key)}).sorted(by: {self.upvalues[$0.2!]!.0 < self.upvalues[$1.2!]!.0}),
                stackSize: stackSize, numParams: numParams,
                isVararg: isVararg, name: name,
                lineDefined: lineDefined, lastLineDefined: lastLineDefined,
                lineinfo: lineinfo, locals: localinfo.map({($0.name, Int32($0.startpc), Int32($0.endpc))}))
        }
    }

    internal class Block {
        fileprivate enum State {
            case normal
            case `if`
            case `while`
            case `repeat`
            case forRange
            case forIter
            case `do`
        }

        internal let fn: Function
        fileprivate let parent: Block?
        private let base: Int
        fileprivate var level: Int
        private var top: Int
        fileprivate var locals = [String: (Int, LocalInfo)]()
        fileprivate var state = State.normal
        private var start: Int? = nil
        private var whileStart: Int? = nil
        private var ifJumps = [Int]()
        private var loopBreaks = [Int]()
        private var childBlock: Block? = nil
        private var forIterLocals: Int? = nil

        fileprivate init(for fn: Function) {
            self.fn = fn
            self.parent = nil
            self.base = 0
            self.level = 0
            self.top = 0
        }

        fileprivate init(in block: Block) {
            self.fn = block.fn
            self.parent = block
            self.base = block.level
            self.level = block.level
            self.top = block.level
        }

        private func allocate(slot: Int) {
            fn.allocate(slot: slot)
            top = slot + 1
        }

        fileprivate func variable(named name: String) -> (VarType, Int) {
            if let local = locals[name] {
                local.1.endpc = fn.top + 1
                return (.local, local.0)
            } else if let parent = parent {
                let v = parent.variable(named: name)
                if v.0 == .global || v.0 == .globalLocal, let env = locals["_ENV"] {
                    env.1.endpc = fn.top + 1
                    return (.globalLocal, env.0)
                } else {
                    return v
                }
            } else {
                let v = fn.upvalue(named: name)
                if v.0 == .global || v.0 == .globalLocal, let env = locals["_ENV"] {
                    env.1.endpc = fn.top + 1
                    return (.globalLocal, env.0)
                } else {
                    return v
                }
            }
        }

        internal func local(named name: String) -> Int {
            let info = LocalInfo(name, fn.top)
            let idx: Int
            if let loc = locals[name] {
                idx = loc.0
            } else {
                idx = level
                level += 1
            }
            locals[name] = (idx, info)
            fn.localinfo.append(info)
            return idx
        }

        private func rk(for v: LuaValue, at idx: Int) -> UInt16 {
            let k = fn.constant(for: v)
            if k < 256 {return UInt16(0x100 | k)}
            allocate(slot: idx)
            if k >= 1 << 18 {
                _ = fn.add(opcode: .iABC(.LOADKX, UInt8(idx), 0, 0))
                _ = fn.add(opcode: .iAx(.EXTRAARG, UInt32(k)))
            } else {
                _ = fn.add(opcode: .iABx(.LOADK, UInt8(idx), UInt32(k)))
            }
            return UInt16(idx)
        }

        private func rk(for expr: LuaParser.Expression, at idx: Int) -> UInt16 {
            if case let .constant(v) = expr {
                return rk(for: v, at: idx)
            } else if case let .prefixexp(pexp) = expr, case let .name(name) = pexp {
                let (type, k) = variable(named: name)
                switch type {
                    case .local: return UInt16(k)
                    case .upvalue:
                        allocate(slot: idx)
                        _ = fn.add(opcode: .iABC(.GETUPVAL, UInt8(idx), UInt16(k), 0))
                        return UInt16(idx)
                    case .global:
                        allocate(slot: idx)
                        _ = fn.add(opcode: .iABC(.GETTABUP, UInt8(idx), UInt16(k), rk(for: .string(.string(name)), at: idx)))
                        return UInt16(idx)
                    case .globalLocal:
                        allocate(slot: idx)
                        _ = fn.add(opcode: .iABC(.GETTABLE, UInt8(idx), UInt16(k), rk(for: .string(.string(name)), at: idx)))
                        return UInt16(idx)
                }
            } else {
                allocate(slot: idx)
                expression(expr, to: idx)
                return UInt16(idx)
            }
        }

        internal func prefixexp(_ expr: LuaParser.PrefixExpression, to idx: Int, results: Int = 1) {
            if results > 0 {allocate(slot: idx + results - 1)}
            switch expr {
                case .name(let name):
                    let (type, vidx) = variable(named: name)
                    switch type {
                        case .local: _ = fn.add(opcode: .iABC(.MOVE, UInt8(idx), UInt16(vidx), 0))
                        case .upvalue: _ = fn.add(opcode: .iABC(.GETUPVAL, UInt8(idx), UInt16(vidx), 0))
                        case .global: _ = fn.add(opcode: .iABC(.GETTABUP, UInt8(idx), UInt16(vidx), rk(for: .string(.string(name)), at: idx)))
                        case .globalLocal: _ = fn.add(opcode: .iABC(.GETTABLE, UInt8(idx), UInt16(vidx), rk(for: .string(.string(name)), at: idx)))
                    }
                    if results > 1 {
                        _ = fn.add(opcode: .iABC(.LOADNIL, UInt8(idx + 1), UInt16(results - 2), 0))
                    }
                case .index(let pexp, let iexp):
                    // TODO: GETTABUP optimization
                    prefixexp(pexp, to: idx)
                    if case let .constant(val) = iexp {
                        _ = fn.add(opcode: .iABC(.GETTABLE, UInt8(idx), UInt16(idx), rk(for: val, at: idx + 1)))
                    } else {
                        expression(iexp, to: idx + 1)
                        _ = fn.add(opcode: .iABC(.GETTABLE, UInt8(idx), UInt16(idx), UInt16(idx + 1)))
                    }
                    if results > 1 {
                        _ = fn.add(opcode: .iABC(.LOADNIL, UInt8(idx + 1), UInt16(results - 2), 0))
                    }
                case .field(let pexp, let name):
                    if case let .name(vname) = pexp {
                        let (type, vidx) = variable(named: vname)
                        switch type {
                            case .local: _ = fn.add(opcode: .iABC(.GETTABLE, UInt8(idx), UInt16(vidx), rk(for: .string(.string(name)), at: idx)))
                            case .upvalue: _ = fn.add(opcode: .iABC(.GETTABUP, UInt8(idx), UInt16(vidx), rk(for: .string(.string(name)), at: idx)))
                            case .global:
                                _ = fn.add(opcode: .iABC(.GETTABUP, UInt8(idx), UInt16(vidx), rk(for: .string(.string(vname)), at: idx)))
                                _ = fn.add(opcode: .iABC(.GETTABLE, UInt8(idx), UInt16(idx), rk(for: .string(.string(name)), at: idx + 1)))
                            case .globalLocal:
                                _ = fn.add(opcode: .iABC(.GETTABLE, UInt8(idx), UInt16(vidx), rk(for: .string(.string(vname)), at: idx)))
                                _ = fn.add(opcode: .iABC(.GETTABLE, UInt8(idx), UInt16(idx), rk(for: .string(.string(name)), at: idx + 1)))
                        }
                    } else {
                        prefixexp(pexp, to: idx)
                        _ = fn.add(opcode: .iABC(.GETTABLE, UInt8(idx), UInt16(idx), rk(for: .string(.string(name)), at: idx + 1)))
                    }
                    if results > 1 {
                        _ = fn.add(opcode: .iABC(.LOADNIL, UInt8(idx + 1), UInt16(results - 2), 0))
                    }
                case .call(let pexp, let args):
                    allocate(slot: max(idx + args.count, idx + results - 1))
                    prefixexp(pexp, to: idx)
                    var vararg = false
                    loop: for (i, v) in args.enumerated() {
                        if i == args.count - 1 {
                            switch v {
                                case .prefixexp(.call), .prefixexp(.callSelf), .vararg:
                                    expression(v, to: idx + i + 1, results: -1)
                                    vararg = true
                                    break loop
                                default: break
                            }
                        }
                        expression(v, to: idx + i + 1)
                    }
                    _ = fn.add(opcode: .iABC(.CALL, UInt8(idx), UInt16(vararg ? 0 : args.count + 1), UInt16(results + 1)))
                case .callSelf(let pexp, let name, let args):
                    allocate(slot: idx + 1)
                    prefixexp(pexp, to: idx)
                    _ = fn.add(opcode: .iABC(.SELF, UInt8(idx), UInt16(idx), rk(for: .string(.string(name)), at: idx + 1)))
                    var vararg = false
                    loop: for (i, v) in args.enumerated() {
                        if i == args.count - 1 {
                            switch v {
                                case .prefixexp(.call), .prefixexp(.callSelf), .vararg:
                                    expression(v, to: idx + i + 2, results: -1)
                                    vararg = true
                                    break loop
                                default: break
                            }
                        }
                        expression(v, to: idx + i + 2)
                    }
                    _ = fn.add(opcode: .iABC(.CALL, UInt8(idx), UInt16(vararg ? 0 : args.count + 2), UInt16(results + 1)))
                case .paren(let exp):
                    expression(exp, to: idx)
                    if results > 1 {
                        _ = fn.add(opcode: .iABC(.LOADNIL, UInt8(idx + 1), UInt16(results - 2), 0))
                    }
            }
        }

        private func int2fb(_ x: Int) -> UInt16 {
            var x = x
            var e = 0
            if x < 8 {return UInt16(x)}
            while x >= 0x10 {
                x = (x+1) >> 1
                e+=1
            }
            return UInt16(((e+1) << 3) | (x - 8))
        }

        internal func insert(expression expr: LuaParser.Expression, to idx: Int) {
            switch expr {
                case .nil, .true, .false, .vararg, .constant, .function:
                    return expression(expr, to: idx)
                case .prefixexp(let pexp):
                    switch pexp {
                        case .name(let name):
                            let (type, vidx) = variable(named: name)
                            switch type {
                                case .local: _ = fn.add(opcode: .iABC(.MOVE, UInt8(idx), UInt16(vidx), 0))
                                case .upvalue: _ = fn.add(opcode: .iABC(.GETUPVAL, UInt8(idx), UInt16(vidx), 0))
                                case .global: _ = fn.add(opcode: .iABC(.GETTABUP, UInt8(idx), UInt16(vidx), rk(for: .string(.string(name)), at: idx)))
                                case .globalLocal: _ = fn.add(opcode: .iABC(.GETTABLE, UInt8(idx), UInt16(vidx), rk(for: .string(.string(name)), at: idx)))
                            }
                            return
                        case .field(.name(let name), let field):
                            let (type, vidx) = variable(named: name)
                            switch type {
                                case .local: _ = fn.add(opcode: .iABC(.MOVE, UInt8(idx), UInt16(vidx), 0))
                                case .upvalue: _ = fn.add(opcode: .iABC(.GETUPVAL, UInt8(idx), UInt16(vidx), 0))
                                case .global: _ = fn.add(opcode: .iABC(.GETTABUP, UInt8(idx), UInt16(vidx), rk(for: .string(.string(name)), at: idx)))
                                case .globalLocal: _ = fn.add(opcode: .iABC(.GETTABLE, UInt8(idx), UInt16(vidx), rk(for: .string(.string(name)), at: idx)))
                            }
                            _ = fn.add(opcode: .iABC(.GETTABLE, UInt8(idx), UInt16(idx), rk(for: .string(.string(field)), at: idx + 1)))
                            return
                        default: break
                    }
                    fallthrough
                default:
                    expression(expr, to: level)
                    if idx != level {
                        _ = fn.add(opcode: .iABC(.MOVE, UInt8(idx), UInt16(level), 0))
                    }
            }
        }

        internal func expression(_ expr: LuaParser.Expression, to idx: Int, results: Int = 1) {
            if results > 0 {allocate(slot: idx + results - 1)}
            switch expr {
                case .nil:
                    _ = fn.add(opcode: .iABC(.LOADNIL, UInt8(idx), UInt16(results - 1), 0))
                case .true:
                    _ = fn.add(opcode: .iABC(.LOADBOOL, UInt8(idx), 1, 0))
                    if results > 1 {
                        _ = fn.add(opcode: .iABC(.LOADNIL, UInt8(idx + 1), UInt16(results - 2), 0))
                    }
                case .false:
                    _ = fn.add(opcode: .iABC(.LOADBOOL, UInt8(idx), 0, 0))
                    if results > 1 {
                        _ = fn.add(opcode: .iABC(.LOADNIL, UInt8(idx + 1), UInt16(results - 2), 0))
                    }
                case .vararg:
                    _ = fn.add(opcode: .iABC(.VARARG, UInt8(idx), UInt16(results + 1), 0))
                case .constant(let val):
                    let k = fn.constant(for: val)
                    if k >= 1 << 18 {
                        _ = fn.add(opcode: .iABC(.LOADKX, UInt8(idx), 0, 0))
                        _ = fn.add(opcode: .iAx(.EXTRAARG, UInt32(k)))
                    } else {
                        _ = fn.add(opcode: .iABx(.LOADK, UInt8(idx), UInt32(k)))
                    }
                    if results > 1 {
                        _ = fn.add(opcode: .iABC(.LOADNIL, UInt8(idx + 1), UInt16(results - 2), 0))
                    }
                case .function(let pidx):
                    _ = fn.add(opcode: .iABx(.CLOSURE, UInt8(idx), UInt32(pidx)))
                    if results > 1 {
                        _ = fn.add(opcode: .iABC(.LOADNIL, UInt8(idx + 1), UInt16(results - 2), 0))
                    }
                case .prefixexp(let pexp):
                    return prefixexp(pexp, to: idx, results: results)
                case .table(let tab):
                    if tab.count == 0 {
                        _ = fn.add(opcode: .iABC(.NEWTABLE, UInt8(idx), 0, 0))
                        if results > 1 {
                            _ = fn.add(opcode: .iABC(.LOADNIL, UInt8(idx + 1), UInt16(results - 2), 0))
                        }
                        return
                    }
                    var aitems = [LuaParser.Expression]()
                    var hitems = [LuaParser.TableEntry]()
                    for e in tab {
                        if case let .array(item) = e {aitems.append(item)}
                        else {hitems.append(e)}
                    }
                    allocate(slot: idx)
                    _ = fn.add(opcode: .iABC(.NEWTABLE, UInt8(idx), int2fb(aitems.count), int2fb(hitems.count)))
                    if !aitems.isEmpty {
                        allocate(slot: idx + min(aitems.count, 50) + 1)
                        var start = 0
                        while start + 50 < aitems.count {
                            for i in 0..<50 {
                                expression(aitems[start+i], to: idx + i + 1)
                            }
                            _ = fn.add(opcode: .iABC(.SETLIST, UInt8(idx), UInt16(50), UInt16(start / 50 + 1)))
                            start += 50
                        }
                        var vararg = false
                        for i in start..<aitems.count {
                            if i == aitems.count - 1 {
                                switch aitems[i] {
                                    case .vararg, .prefixexp(.call), .prefixexp(.callSelf):
                                        expression(aitems[i], to: idx + (i - start) + 1, results: -1)
                                        vararg = true
                                    default: expression(aitems[i], to: idx + (i - start) + 1)
                                }
                            } else {
                                expression(aitems[i], to: idx + (i - start) + 1)
                            }
                        }
                        _ = fn.add(opcode: .iABC(.SETLIST, UInt8(idx), vararg ? 0 : UInt16(aitems.count - start), UInt16(start / 50 + 1)))
                    }
                    for e in hitems {
                        switch e {
                            case .field(let name, let val):
                                let vidx: UInt16
                                if case let .constant(v) = val {
                                    vidx = rk(for: v, at: idx + 1)
                                } else {
                                    allocate(slot: idx + 1)
                                    expression(val, to: idx + 1)
                                    vidx = UInt16(idx + 1)
                                }
                                _ = fn.add(opcode: .iABC(.SETTABLE, UInt8(idx), rk(for: .string(.string(name)), at: idx + 2), vidx))
                            case .keyed(let key, let val):
                                let kidx: UInt16, vidx: UInt16
                                if case let .constant(k) = key {
                                    kidx = rk(for: k, at: idx + 1)
                                } else {
                                    allocate(slot: idx + 1)
                                    expression(key, to: idx + 1)
                                    kidx = UInt16(idx + 1)
                                }
                                if case let .constant(v) = val {
                                    vidx = rk(for: v, at: idx + 2)
                                } else {
                                    allocate(slot: idx + 2)
                                    expression(val, to: idx + 2)
                                    vidx = UInt16(idx + 2)
                                }
                                _ = fn.add(opcode: .iABC(.SETTABLE, UInt8(idx), kidx, vidx))
                            case .array: assert(false)
                        }
                    }
                    if results > 1 {
                        _ = fn.add(opcode: .iABC(.LOADNIL, UInt8(idx + 1), UInt16(results - 2), 0))
                    }
                case .binop(let oper, let left, let right):
                    if oper == .concat {
                        expression(left, to: idx)
                        var node = right
                        var end = idx + 1
                        while case let .binop(op, l, r) = node, op == .concat {
                            expression(l, to: end)
                            end += 1
                            node = r
                        }
                        expression(node, to: end)
                        _ = fn.add(opcode: .iABC(.CONCAT, UInt8(idx), UInt16(idx), UInt16(end)))
                        return
                    } else if oper == .and || oper == .or {
                        expression(left, to: idx)
                        _ = fn.add(opcode: .iABC(.TEST, UInt8(idx), 0, oper == .and ? 0 : 1))
                        let jmp = fn.add(opcode: .iAsBx(.JMP, 0, 0)) - 1
                        expression(right, to: idx)
                        fn.modify(at: jmp, opcode: .iAsBx(.JMP, 0, Int32(fn.top - jmp - 1)))
                        return
                    }
                    let lidx = rk(for: left, at: idx)
                    let ridx = rk(for: right, at: idx + 1)
                    let op: LuaOpcode.Operation
                    switch oper {
                        case .add: op = .ADD
                        case .sub: op = .SUB
                        case .mul: op = .MUL
                        case .div: op = .DIV
                        case .mod: op = .MOD
                        case .pow: op = .POW
                        case .eq, .ne, .gt, .lt, .ge, .le:
                            let flip: Bool, op: LuaOpcode.Operation, a: UInt8
                            switch oper {
                                case .eq: op = .EQ; flip = false; a = 1
                                case .ne: op = .EQ; flip = false; a = 0
                                case .lt: op = .LT; flip = false; a = 1
                                case .ge: op = .LE; flip = true;  a = 1
                                case .le: op = .LE; flip = false; a = 1
                                case .gt: op = .LT; flip = true;  a = 1
                                default: assert(false); return
                            }
                            _ = fn.add(opcode: .iABC(op, a, flip ? ridx : lidx, flip ? lidx : ridx))
                            _ = fn.add(opcode: .iABC(.LOADBOOL, UInt8(idx), UInt16(1), UInt16(1)))
                            _ = fn.add(opcode: .iABC(.LOADBOOL, UInt8(idx), UInt16(0), UInt16(0)))
                            return
                        default: assert(false); return
                    }
                    _ = fn.add(opcode: .iABC(op, UInt8(idx), lidx, ridx))
                case .unop(let oper, let exp):
                    if case let .prefixexp(.name(name)) = exp {
                        let (type, lidx) = variable(named: name)
                        if type == .local {
                            let op: LuaOpcode.Operation
                            switch oper {
                                case .len: op = .LEN
                                case .sub: op = .UNM
                                case .not: op = .NOT
                                default: assert(false); return
                            }
                            _ = fn.add(opcode: .iABC(op, UInt8(idx), UInt16(lidx), 0))
                            return
                        }
                    }
                    expression(exp, to: idx)
                    let op: LuaOpcode.Operation
                    switch oper {
                        case .len: op = .LEN
                        case .sub: op = .UNM
                        case .not: op = .NOT
                        default: assert(false); return
                    }
                    _ = fn.add(opcode: .iABC(op, UInt8(idx), UInt16(idx), 0))
            }
        }

        internal func assign(to vars: [LuaParser.PrefixExpression], from explist: [LuaParser.Expression]) {
            assert(state == .normal)
            if vars.count == 1, case let .name(name) = vars[0] {
                let (type, idx) = variable(named: name)
                if type == .local {
                    switch explist[0] {
                        case .constant, .false, .true, .nil, .vararg:
                            expression(explist[0], to: idx)
                            for i in 1..<explist.count {
                                expression(explist[i], to: level)
                            }
                            return
                        default: break
                    }
                }
            } else if vars.count == 1, case let .field(pexp, field) = vars[0], case let .name(name) = pexp {
                let (type, idx) = variable(named: name)
                if type == .local {
                    for i in 1..<explist.count {
                        expression(explist[i], to: level)
                    }
                    let k = rk(for: .string(.string(field)), at: level + 1)
                    expression(explist[0], to: level)
                    _ = fn.add(opcode: .iABC(.SETTABLE, UInt8(idx), k, UInt16(level)))
                    return
                }
            } else if vars.count == 1,
              case let .index(pexp, idxp) = vars[0],
              case let .name(name) = pexp,
              case let .prefixexp(.name(index)) = idxp {
                let (type, idx) = variable(named: name)
                let (itype, iidx) = variable(named: index)
                if type == .local && itype == .local {
                    for i in 1..<explist.count {
                        expression(explist[i], to: level)
                    }
                    expression(explist[0], to: level)
                    _ = fn.add(opcode: .iABC(.SETTABLE, UInt8(idx), UInt16(iidx), UInt16(level)))
                    return
                }
            }
            var tables = 0, nexttable = 0
            for v in vars {
                switch v {
                    case .field(let exp, _):
                        prefixexp(exp, to: level + tables)
                        tables += 1
                    case .index(let exp, let key):
                        prefixexp(exp, to: level + tables)
                        expression(key, to: level + tables + 1)
                        tables += 2
                    default: ()
                }
            }
            for (i, v) in explist.enumerated() {
                expression(v, to: level + i + tables, results: (vars.count >= explist.count && i == explist.count - 1) ? vars.count - explist.count + 1 : 1)
            }
            for (i, v) in vars.enumerated() {
                switch v {
                    case .name(let name):
                        let (type, idx) = variable(named: name)
                        switch type {
                            case .local: _ = fn.add(opcode: .iABC(.MOVE, UInt8(idx), UInt16(level + i + tables), 0))
                            case .upvalue: _ = fn.add(opcode: .iABC(.SETUPVAL, UInt8(level + i + tables), UInt16(idx), 0))
                            case .global: _ = fn.add(opcode: .iABC(.SETTABUP, UInt8(idx), rk(for: .string(.string(name)), at: level + i + tables + 1), UInt16(level + i + tables)))
                            case .globalLocal: _ = fn.add(opcode: .iABC(.SETTABLE, UInt8(idx), rk(for: .string(.string(name)), at: level + i + tables + 1), UInt16(level + i + tables)))
                        }
                    case .field(_, let name):
                        _ = fn.add(opcode: .iABC(.SETTABLE, UInt8(level + nexttable), rk(for: .string(.string(name)), at: level + i + tables + 1), UInt16(level + i + tables)))
                        nexttable += 1
                    case .index:
                        _ = fn.add(opcode: .iABC(.SETTABLE, UInt8(level + nexttable), UInt16(level + nexttable + 1), UInt16(level + i + tables)))
                        nexttable += 2
                    default: assert(false)
                }
            }
        }

        internal func local(named names: [String], values: [LuaParser.Expression] = []) {
            assert(state == .normal)
            allocate(slot: level + names.count - 1)
            if values.isEmpty {
                _ = fn.add(opcode: .iABC(.LOADNIL, UInt8(level), UInt16(names.count - 1), 0))
                for (_, v) in names.enumerated() {
                    let info = LocalInfo(v, fn.top)
                    let idx: Int
                    if let loc = locals[v] {
                        idx = loc.0
                    } else {
                        idx = level
                        level += 1
                    }
                    locals[v] = (idx, info)
                    fn.localinfo.append(info)
                }
                return
            }
            var localsToSet = [(Int, LocalInfo)]()
            for (i, v) in names.enumerated() {
                if i == values.count - 1 && names.count > values.count {
                    let pc = fn.top
                    expression(values[i], to: level, results: names.count - values.count + 1)
                    for j in i..<names.count {
                        let info = LocalInfo(names[j], pc)
                        locals[names[j]] = (level + j - i, info)
                        fn.localinfo.append(info)
                    }
                    level += names.count - i
                    break
                }
                let idx: Int
                let pc = fn.top
                /*if let loc = locals[v] {
                    idx = loc.0
                    insert(expression: values[i], to: idx)
                } else*/ do {
                    idx = level
                    expression(values[i], to: level)
                    level += 1
                }
                let info = LocalInfo(v, pc)
                localsToSet.append((idx, info))
            }
            for local in localsToSet {
                locals[local.1.name] = local
                fn.localinfo.append(local.1)
            }
            if names.count < values.count {
                for i in names.count..<values.count {
                    expression(values[i], to: level)
                }
            }
        }

        internal func call(_ expr: LuaParser.PrefixExpression) {
            assert(state == .normal)
            prefixexp(expr, to: level, results: 0)
        }

        internal func `do`() -> Block {
            assert(state == .normal)
            state = .do
            childBlock = Block(in: self)
            return childBlock!
        }

        internal func endDo() {
            assert(state == .do)
            if childBlock!.level > level {
                let close = fn.close(to: level)
                if close != 0 {
                    _ = fn.add(opcode: .iAsBx(.JMP, close, 0))
                }
            }
            state = .normal
        }

        internal func `break`() throws {
            var parent = parent
            while parent != nil {
                switch parent!.state {
                    case .while, .repeat, .forIter, .forRange:
                        parent!.loopBreaks.append(fn.add(opcode: .iAsBx(.JMP, 0, 0)) - 1)
                        return
                    default: break
                }
                parent = parent!.parent
            }
            throw LuaParser.Error.codeError(message: "no loop to break")
        }

        internal func label(named name: String) throws {
            try fn.add(label: name, in: self)
            level = top
        }

        internal func `goto`(_ name: String) throws {
            try fn.goto(name, in: self)
        }

        internal func `if`(_ expr: LuaParser.Expression) -> Block {
            assert(state == .normal || state == .if)
            if let start = start {
                let end = fn.add(opcode: .iAsBx(.JMP, childBlock!.level > level ? fn.close(to: level) : 0, 0)) - 1
                ifJumps.append(end)
                fn.modify(at: start, opcode: .iAsBx(.JMP, 0, Int32(end - start)))
            }
            if case let .binop(oper, left, right) = expr {
                switch oper {
                    case .eq, .ne, .gt, .lt, .ge, .le:
                        let lidx = rk(for: left, at: level)
                        let ridx = rk(for: right, at: level + 1)
                        let flip: Bool, op: LuaOpcode.Operation, a: UInt8
                        switch oper {
                            case .eq: op = .EQ; flip = false; a = 0
                            case .ne: op = .EQ; flip = false; a = 1
                            case .lt: op = .LT; flip = false; a = 0
                            case .ge: op = .LE; flip = true;  a = 0
                            case .le: op = .LE; flip = false; a = 0
                            case .gt: op = .LT; flip = true;  a = 0
                            default: assert(false); return Block(in: self)
                        }
                        _ = fn.add(opcode: .iABC(op, a, flip ? ridx : lidx, flip ? lidx : ridx))
                        start = fn.add(opcode: .iAsBx(.JMP, 0, 0)) - 1
                        state = .if
                        childBlock = Block(in: self)
                        return childBlock!
                    // TODO: optimize and/or chains
                    default: break
                }
            }
            expression(expr, to: level)
            _ = fn.add(opcode: .iABC(.TEST, UInt8(level), 0, 0))
            start = fn.add(opcode: .iAsBx(.JMP, 0, 0)) - 1
            state = .if
            childBlock = Block(in: self)
            return childBlock!
        }

        internal func `else`() -> Block {
            assert(state == .if)
            if let start = start {
                let end = fn.add(opcode: .iAsBx(.JMP, childBlock!.level > level ? fn.close(to: level) : 0, 0)) - 1
                ifJumps.append(end)
                fn.modify(at: start, opcode: .iAsBx(.JMP, 0, Int32(end - start)))
            }
            start = nil
            childBlock = Block(in: self)
            return childBlock!
        }

        internal func endIf() {
            assert(state == .if)
            if let start = start {
                fn.modify(at: start, opcode: .iAsBx(.JMP, 0, Int32(fn.top - start - 1)))
            }
            for j in ifJumps {
                fn.modify(at: j, opcode: .iAsBx(.JMP, childBlock!.level > level ? fn.close(to: level) : 0, Int32(fn.top - j - 1)))
            }
            start = nil
            state = .normal
            childBlock = nil
            ifJumps = [Int]()
        }

        internal func `while`(_ expr: LuaParser.Expression) -> Block {
            assert(state == .normal)
            if case let .binop(oper, left, right) = expr {
                switch oper {
                    case .eq, .ne, .gt, .lt, .ge, .le:
                        whileStart = fn.top
                        let lidx = rk(for: left, at: level)
                        let ridx = rk(for: right, at: level + 1)
                        let flip: Bool, op: LuaOpcode.Operation, a: UInt8
                        switch oper {
                            case .eq: op = .EQ; flip = false; a = 0
                            case .ne: op = .EQ; flip = false; a = 1
                            case .lt: op = .LT; flip = false; a = 0
                            case .ge: op = .LE; flip = true;  a = 0
                            case .le: op = .LE; flip = false; a = 0
                            case .gt: op = .LT; flip = true;  a = 0
                            default: assert(false); return Block(in: self)
                        }
                        _ = fn.add(opcode: .iABC(op, a, flip ? ridx : lidx, flip ? lidx : ridx)) - 1
                        start = fn.add(opcode: .iAsBx(.JMP, 0, 0)) - 1
                        state = .while
                        childBlock = Block(in: self)
                        return childBlock!
                    // TODO: optimize and/or chains
                    default: break
                }
            }
            whileStart = fn.top
            expression(expr, to: level)
            _ = fn.add(opcode: .iABC(.TEST, UInt8(level), 0, 0)) 
            start = fn.add(opcode: .iAsBx(.JMP, 0, 0)) - 1
            state = .while
            loopBreaks = []
            childBlock = Block(in: self)
            return childBlock!
        }

        internal func endWhile() {
            assert(state == .while)
            if let start = start {
                let close = childBlock!.level > level ? fn.close(to: level) : 0
                let end = fn.add(opcode: .iAsBx(.JMP, close, Int32(whileStart! - fn.top - 1))) - 1
                fn.modify(at: start, opcode: .iAsBx(.JMP, 0, Int32(end - start)))
                for idx in loopBreaks {
                    fn.modify(at: idx, opcode: .iAsBx(.JMP, close, Int32(end - idx)))
                }
            }
            start = nil
            state = .normal
            childBlock = nil
        }

        internal func `repeat`() -> Block {
            assert(state == .normal)
            start = fn.top
            state = .repeat
            loopBreaks = []
            childBlock = Block(in: self)
            return childBlock!
        }

        internal func until(_ expr: LuaParser.Expression) {
            assert(state == .repeat)
            if let repeatBlock = childBlock {
                if case let .binop(oper, left, right) = expr {
                    switch oper {
                        case .eq, .ne, .gt, .lt, .ge, .le:
                            let lidx = repeatBlock.rk(for: left, at: repeatBlock.level)
                            let ridx = repeatBlock.rk(for: right, at: repeatBlock.level + 1)
                            let flip: Bool, op: LuaOpcode.Operation, a: UInt8
                            switch oper {
                                case .eq: op = .EQ; flip = false; a = 0
                                case .ne: op = .EQ; flip = false; a = 1
                                case .lt: op = .LT; flip = false; a = 0
                                case .ge: op = .LE; flip = true;  a = 0
                                case .le: op = .LE; flip = false; a = 0
                                case .gt: op = .LT; flip = true;  a = 0
                                default: assert(false); return
                            }
                            _ = fn.add(opcode: .iABC(op, a, flip ? ridx : lidx, flip ? lidx : ridx))
                            let close = childBlock!.level > level ? fn.close(to: level) : 0
                            let end = fn.add(opcode: .iAsBx(.JMP, close, Int32(start! - fn.top - 1))) - 1
                            for idx in loopBreaks {
                                fn.modify(at: idx, opcode: .iAsBx(.JMP, close, Int32(end - idx)))
                            }
                            start = nil
                            state = .normal
                            childBlock = nil
                            return
                        // TODO: optimize and/or chains
                        default: break
                    }
                }
                repeatBlock.expression(expr, to: repeatBlock.level)
                _ = fn.add(opcode: .iABC(.TEST, UInt8(repeatBlock.level), 0, 0))
                let close = childBlock!.level > level ? fn.close(to: level) : 0
                let end = fn.add(opcode: .iAsBx(.JMP, close, Int32(start! - fn.top - 1))) - 1
                for idx in loopBreaks {
                    fn.modify(at: idx, opcode: .iAsBx(.JMP, close, Int32(end - idx)))
                }
            }
            start = nil
            state = .normal
            childBlock = nil
        }

        internal func `return`(_ explist: [LuaParser.Expression]) {
            assert(state == .normal)
            if explist.isEmpty {
                _ = fn.add(opcode: .iABC(.RETURN, 0, 1, 0))
                return
            }
            if explist.count == 1, case let .prefixexp(pexp) = explist[0], case let .call(fn, args) = pexp {
                prefixexp(fn, to: level)
                var vararg = false
                loop: for (i, v) in args.enumerated() {
                    if i == args.count - 1 {
                        switch v {
                            case .prefixexp(.call), .prefixexp(.callSelf), .vararg:
                                expression(v, to: level + i + 1, results: -1)
                                vararg = true
                                break loop
                            default: break
                        }
                    }
                    expression(v, to: level + i + 1)
                }
                _ = self.fn.add(opcode: .iABC(.TAILCALL, UInt8(level), UInt16(vararg ? 0 : args.count + 1), 0))
                return
            }
            if explist.count == 1, case let .prefixexp(.name(name)) = explist[0] {
                let (type, idx) = variable(named: name)
                if type == .local {
                    _ = fn.add(opcode: .iABC(.RETURN, UInt8(idx), 2, 0))
                    return
                }
            }
            var vararg = false
            for (i, v) in explist.enumerated() {
                if i == explist.count - 1, case let .prefixexp(pexp) = v, case .call = pexp {
                    expression(v, to: level + i, results: -1)
                    vararg = true
                } else if i == explist.count - 1, case let .prefixexp(pexp) = v, case .callSelf = pexp {
                    expression(v, to: level + i, results: -1)
                    vararg = true
                } else if i == explist.count - 1, case .vararg = v {
                    expression(v, to: level + i, results: -1)
                    vararg = true
                } else {
                    expression(v, to: level + i)
                }
            }
            _ = fn.add(opcode: .iABC(.RETURN, UInt8(level), UInt16(vararg ? 0 : explist.count + 1), 0))
        }

        internal func forRange(named name: String, start: LuaParser.Expression, stop: LuaParser.Expression, step: LuaParser.Expression?) -> Block {
            assert(state == .normal)
            allocate(slot: level + 3)
            expression(start, to: level)
            expression(stop, to: level + 1)
            if let step = step {
                expression(step, to: level + 2)
            } else {
                _ = fn.add(opcode: .iABx(.LOADK, UInt8(level + 2), UInt32(fn.constant(for: .number(1)))))
            }
            self.start = fn.add(opcode: .iAsBx(.FORPREP, UInt8(level), 0)) - 1
            state = .forRange
            loopBreaks = []
            let block = Block(in: self)
            _ = block.local(named: "(for index)")
            _ = block.local(named: "(for limit)")
            _ = block.local(named: "(for step)")
            _ = block.local(named: name)
            return block
        }

        internal func endForRange() {
            assert(state == .forRange)
            if let start = start {
                let close = fn.close(to: level + 3)
                if close != 0 {
                    _ = fn.add(opcode: .iAsBx(.JMP, close, 0))
                }
                let end = fn.add(opcode: .iAsBx(.FORLOOP, UInt8(level), Int32(start - fn.top))) - 1
                fn.modify(at: start, opcode: .iAsBx(.FORPREP, UInt8(level), Int32(end - start - 1)))
                for idx in loopBreaks {
                    fn.modify(at: idx, opcode: .iAsBx(.JMP, close, Int32(end - idx)))
                }
            }
            start = nil
            state = .normal
        }

        internal func forIter(names: [String], from explist: [LuaParser.Expression]) -> Block {
            assert(state == .normal)
            allocate(slot: level + 2 + names.count)
            switch explist.count {
                case 1:
                    expression(explist[0], to: level, results: 3)
                case 2:
                    expression(explist[0], to: level)
                    expression(explist[1], to: level + 1, results: 2)
                default:
                    expression(explist[0], to: level)
                    expression(explist[1], to: level + 1)
                    expression(explist[2], to: level + 2)
                    for i in 3..<explist.count {
                        expression(explist[i], to: level + 3) // ignored
                    }
            }
            start = fn.add(opcode: .iAsBx(.JMP, 0, 0)) - 1
            state = .forIter
            loopBreaks = []
            forIterLocals = names.count
            let block = Block(in: self)
            _ = block.local(named: "(for generator)")
            _ = block.local(named: "(for state)")
            _ = block.local(named: "(for control)")
            for name in names {_ = block.local(named: name)}
            return block
        }

        internal func endForIter() {
            assert(state == .forIter)
            if let start = start, let forIterLocals = forIterLocals {
                let close = fn.close(to: level + 3)
                if close != 0 {
                    _ = fn.add(opcode: .iAsBx(.JMP, close, 0))
                }
                let end = fn.add(opcode: .iABC(.TFORCALL, UInt8(level), 0, UInt16(forIterLocals)))
                _ = fn.add(opcode: .iAsBx(.TFORLOOP, UInt8(level + 2), Int32(start - end)))
                fn.modify(at: start, opcode: .iAsBx(.JMP, 0, Int32(end - start - 2)))
                for idx in loopBreaks {
                    fn.modify(at: idx, opcode: .iAsBx(.JMP, close, Int32(end - idx)))
                }
            }
            start = nil
            state = .normal
            forIterLocals = nil
        }

        internal func function(with args: [String], vararg: Bool) -> (Block, Int) {
            let fn2 = Function(from: self, args: args.count, vararg: vararg)
            for name in args {_ = fn2.root.local(named: name)}
            return (fn2.root, fn.add(prototype: fn2))
        }

        internal func localFunction(named name: String, with args: [String], vararg: Bool) -> Block {
            assert(state == .normal)
            let idx = local(named: name)
            let (fn2, pidx) = function(with: args, vararg: vararg)
            _ = fn.add(opcode: .iABx(.CLOSURE, UInt8(idx), UInt32(pidx)))
            return fn2
        }
    }

    private let root: Function
    private var block: Block
    private var blockStack = [Block]()

    internal static func test() -> LuaInterpretedFunction {
        let coder = LuaCode(named: "test")
        coder.local(named: ["test"], values: [.constant(.number(2))])

        coder.if(.binop(.eq, .prefixexp(.name("test")), .constant(.number(2))))
            coder.call(.call(.name("print"), [.constant(.string(.string("Hello World!")))]))
        coder.else()
            coder.call(.call(.name("print"), [.constant(.string(.string("Failure")))]))
        try! coder.end()

        coder.while(.binop(.lt, .prefixexp(.name("test")), .constant(.number(5))))
            coder.call(.call(.name("print"), [.constant(.string(.string("Loop:"))), .prefixexp(.name("test"))]))
            coder.assign(to: [.name("test")], from: [.binop(.add, .prefixexp(.name("test")), .constant(.number(1)))])
        try! coder.end()

        coder.forRange(named: "i", start: .constant(.number(1)), stop: .constant(.number(5)), step: nil)
            coder.call(.call(.name("print"), [.prefixexp(.name("i"))]))
        try! coder.end()

        coder.forIter(names: ["k", "v"], from: [.prefixexp(.call(.name("pairs"), [.prefixexp(.name("string"))]))])
            coder.call(.call(.name("print"), [.prefixexp(.name("k")), .prefixexp(.name("v"))]))
            coder.if(.binop(.eq, .prefixexp(.name("k")), .constant(.string(.string("match")))))
                try! coder.break()
            try! coder.end()
        try! coder.end()

        coder.function(local: "foo", with: ["a"], vararg: false)
            try! coder.label(named: "loop")
            coder.if(.binop(.lt, .prefixexp(.name("a")), .constant(.number(10))))
                coder.call(.call(.name("print"), [.prefixexp(.name("a"))]))
                coder.assign(to: [.name("a")], from: [.binop(.add, .prefixexp(.name("a")), .constant(.number(1)))])
                try! coder.goto("loop")
            try! coder.end()
            coder.return([.prefixexp(.name("foo"))])
        try! coder.end()
        coder.call(.call(.name("foo"), [.prefixexp(.name("test"))]))

        coder.return([.true])
        try! coder.end()
        return coder.encode()
    }

    internal init(named name: [UInt8]) {
        root = Function(named: name)
        block = root.root
    }

    internal var line: Int {
        get {
            return block.fn.line
        } set (value) {
            block.fn.line = value
        }
    }

    internal func encode() -> LuaInterpretedFunction {
        return root.encode()
    }

    internal func assign(to vars: [LuaParser.PrefixExpression], from explist: [LuaParser.Expression]) {
        return block.assign(to: vars, from: explist)
    }

    internal func call(_ expr: LuaParser.PrefixExpression) {
        return block.call(expr)
    }

    internal func label(named name: String) throws {
        return try block.label(named: name)
    }

    internal func `goto`(_ name: String) throws {
        return try block.goto(name)
    }

    internal func `break`() throws {
        return try block.break()
    }
    
    internal func `do`() {
        block = block.do()
    }

    internal func `while`(_ expr: LuaParser.Expression) {
        block = block.while(expr)
    }

    internal func `repeat`() {
        block = block.repeat()
    }

    internal func until(_ expr: LuaParser.Expression) {
        if let parent = block.parent {
            for (_, (_, local)) in block.locals {
                local.active = false
            }
            parent.until(expr)
            block = parent
        }
    }

    internal func `if`(_ expr: LuaParser.Expression) {
        block = block.if(expr)
    }

    internal func elseif(_ expr: LuaParser.Expression) {
        if let parent = block.parent {
            for (_, (_, local)) in block.locals {
                local.active = false
            }
            block = parent
        }
        block = block.if(expr)
    }

    internal func `else`() {
        if let parent = block.parent {
            for (_, (_, local)) in block.locals {
                local.active = false
            }
            block = parent
        }
        block = block.else()
    }

    internal func forRange(named name: String, start: LuaParser.Expression, stop: LuaParser.Expression, step: LuaParser.Expression?) {
        block = block.forRange(named: name, start: start, stop: stop, step: step)
    }

    internal func forIter(names: [String], from explist: [LuaParser.Expression]) {
        block = block.forIter(names: names, from: explist)
    }

    internal func function(named names: [String], with args: [String], vararg: Bool) {
        let (fn, idx) = block.function(with: args, vararg: vararg)
        var pexp = LuaParser.PrefixExpression.name(names.first!)
        for i in 1..<names.count-1 {
            pexp = .field(pexp, names[i])
        }
        block.assign(to: [pexp], from: [.function(idx)])
        blockStack.append(block)
        block = fn
    }

    internal func function(local name: String, with args: [String], vararg: Bool) {
        blockStack.append(block)
        block = block.localFunction(named: name, with: args, vararg: vararg)
    }

    internal func function(with args: [String], vararg: Bool) -> Int {
        let (fn, idx) = block.function(with: args, vararg: vararg)
        blockStack.append(block)
        block = fn
        return idx
    }

    internal func local(named names: [String], values: [LuaParser.Expression] = []) {
        return block.local(named: names, values: values)
    }

    internal func local(named name: String) -> Int {
        return block.local(named: name)
    }

    internal func end() throws {
        for (_, (_, local)) in block.locals {
            local.active = false
        }
        if let parent = block.parent {
            switch parent.state {
                case .if: parent.endIf()
                case .while: parent.endWhile()
                case .forIter: parent.endForIter()
                case .forRange: parent.endForRange()
                case .do: parent.endDo()
                default: break
            }
            block = parent
        } else {
            if block.fn.hasOpenGotos {
                throw LuaParser.Error.gotoError(message: "no visible label for goto")
            }
            block.return([])
            block.fn.lastLineDefined = Int32(block.fn.line)
            if !blockStack.isEmpty {
                block = blockStack.popLast()!
            }
        }
    }

    internal func `return`(_ explist: [LuaParser.Expression]) {
        return block.return(explist)
    }
}