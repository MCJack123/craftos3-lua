public actor LuaThread: Hashable {
    public static func == (lhs: LuaThread, rhs: LuaThread) -> Bool {
        return lhs === rhs
    }

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(Unmanaged.passUnretained(self).toOpaque())
    }

    /// The current state of the coroutine.
    public enum State: Sendable {
        /// Indicates the coroutine is suspended, waiting to be resumed.
        case suspended
        /// Indicates the coroutine is currently running.
        case running
        /// Indicates the coroutine was running, but has resumed antother coroutine and is awaiting its result.
        case normal
        /// Indicates the coroutine returned or threw an error, and is no longer resumable.
        case dead
    }

    /// Error codes for various coroutine functions.
    public enum CoroutineError: Error {
        /// Thrown when `resume` is called while the coroutine is not suspended.
        case notSuspended
        /// Thrown when `yield` is called when no coroutine is running.
        case noCoroutine
        /// Thrown to unwind the call stack when a suspended coroutine is deleted.
        /// Make sure this error can propagate up to the coroutine's main function.
        case cancel
    }

    /// Yields the currently running coroutine to its parent, passing values back and forth with the parent.
    ///
    /// This function may throw `CoroutineError.cancel` if the coroutine is deleted
    /// before the function completes. Make sure to propagate this error up to the
    /// main function, and do not ignore the error - it may cause your code to
    /// continue running!
    ///
    /// - Parameter args: Any arguments to pass as return values to the awaited `resume` call.
    /// - Returns: The arguments passed to the next `resume` call.
    public static func yield(in state: LuaState, with args: [LuaValue] = [LuaValue]()) async throws -> [LuaValue] {
        return try await state.assertThread().yieldIsolated(with: args)
    }

    private func yieldIsolated(with args: [LuaValue]) async throws -> [LuaValue] {
        if state != .running {
            throw CoroutineError.noCoroutine
        }
        state = .suspended
        return try await withCheckedThrowingContinuation {continuation in
            let c = self.continuation!
            self.continuation = continuation
            c.resume(returning: args)
        }
    }

    public static func yield(in state: Lua, with args: [LuaValue] = [LuaValue]()) async throws -> [LuaValue] {
        return try await yield(in: state.luaState, with: args)
    }

    private var task: Task<Void, Error>!
    private var continuation: CheckedContinuation<[LuaValue], Error>!
    internal var callStack = [CallInfo]()
    internal let luaState: LuaState
    internal var hookFunction: LuaFunction?
    internal var hookFlags: Lua.HookFlags = []
    internal var hookCount: Int = 0
    internal var hookCountLeft: Int = 0
    internal var allowHooks = true
    
    /// The current state of the coroutine.
    public private(set) var state: State = .suspended

    // TODO: fix reference cycles in task

    private func initIsolated(for body: LuaFunction) async throws {
        let args = try await withCheckedThrowingContinuation {continuation in
            self.continuation = continuation
        }
        do {
            let res = try await body.call(in: self, with: args)
            self.state = .dead
            self.continuation.resume(returning: res)
            self.continuation = nil
        } catch {
            self.state = .dead
            self.continuation.resume(throwing: error)
            self.continuation = nil
        }
    }

    private func initIsolated(for body: @escaping () async throws -> ()) async throws {
        _ = try await withCheckedThrowingContinuation {continuation in
            self.continuation = continuation
        }
        do {
            try await body()
            self.state = .dead
            self.continuation.resume(returning: [])
            self.continuation = nil
        } catch {
            self.state = .dead
            self.continuation.resume(throwing: error)
            self.continuation = nil
        }
    }

    internal func set(state: State) {
        if self.state != .dead {
            self.state = state
        }
    }

    /// Creates a new coroutine around a Lua function.
    /// 
    /// - Parameter body: The main function of the coroutine.
    public init(in L: LuaState, for body: LuaFunction) async {
        luaState = L
        task = Task {[weak self] in
            try await self?.initIsolated(for: body)
        }
        while continuation == nil {await Task.yield()}
    }

    public init(in L: Lua, for body: LuaFunction) async {
        await self.init(in: L.luaState, for: body)
    }

    /// Creates a new coroutine around a closure which takes no arguments and returns no values.
    /// 
    /// - Parameter body: The main function of the coroutine.
    public init(in L: LuaState, for body: @escaping @Sendable () async throws -> ()) async {
        luaState = L
        task = Task {[weak self] in
            try await self?.initIsolated(for: body)
        }
        while continuation == nil {await Task.yield()}
    }

    public init(in L: Lua, for body: @escaping @Sendable () async throws -> ()) async {
        await self.init(in: L.luaState, for: body)
    }

    internal init(in L: LuaState) {
        luaState = L
        state = .dead
    }

    deinit {
        if state == .suspended {
            continuation.resume(throwing: CoroutineError.cancel)
        }
    }

    /// Resumes the coroutine, passing values back and forth with the coroutine.
    ///
    /// If this is the first resume call on the coroutine, the arguments passed
    /// will be sent as parameters to the body function. Return values are returned
    /// the same way as yield results - to check whether the returned value was
    /// the function's return value, check whether the state is `.dead`.
    /// 
    /// - Parameter args: Any arguments to pass to the coroutine's `yield` call or main function.
    /// - Returns: The values passed to `yield`, or the return values of the main function.
    public func resume(in state: LuaState, with args: [LuaValue] = [LuaValue]()) async throws -> [LuaValue] {
        if self.state != .suspended {
            throw CoroutineError.notSuspended
        }
        self.state = .running
        let old = await state.swap(thread: self, isResuming: true)
        do {
            let res = try await withCheckedThrowingContinuation {nextContinuation in
                let c = continuation!
                continuation = nextContinuation
                c.resume(returning: args)
            }
            _ = await state.swap(thread: old, isResuming: false)
            return res
        } catch {
            _ = await state.swap(thread: old, isResuming: false)
            throw error
        }
    }

    public func resume(in state: Lua, with args: [LuaValue] = [LuaValue]()) async throws -> [LuaValue] {
        return try await resume(in: luaState, with: args)
    }

    public func error(message text: String, at level: Int = 0) async -> Lua.LuaError {
        let idx = callStack.count - level - 1
        if idx >= 0 && idx < callStack.count, let loc = await callStack[idx].location {
            return Lua.LuaError.runtimeError(message: loc + text)
        }
        return Lua.LuaError.runtimeError(message: text)
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

    internal static func getobjname(_ p: LuaInterpretedFunction, _ lastpc: Int, _ reg: UInt8) -> (String, Lua.Debug.NameType)? {
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
                case .iABx(let op, _, let bx):
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

    /* }====================================================== */

    internal func info(with options: Lua.Debug.InfoFlags, in ci: CallInfo?, previous: CallInfo?, for function: LuaFunction, at level: Int?) async -> Lua.Debug {
        var retval = Lua.Debug()
        if options.contains(.name) {
            if let ci = previous, let (name, what) = await ci.getfuncname() {
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
                    if let level = level, level == callStack.count - 1 {
                        retval.what = .main
                    } else {
                        retval.what = .lua
                    }
                    retval.source = cl.proto.name
                    retval.short_src = Lua.shortSource(for: cl)
                    retval.lineDefined = Int(cl.proto.lineDefined)
                    retval.lastLineDefined = Int(cl.proto.lastLineDefined)
                case .swift:
                    retval.what = .swift
                    retval.source = "[C]"
                    retval.short_src = "[C]"
                    retval.lineDefined = -1
                    retval.lastLineDefined = -1
            }
        }
        if options.contains(.line) {
            switch function {
                case .lua(let cl):
                    if let ci = ci {
                        let savedpc = await ci.savedpc
                        if savedpc-1 < cl.proto.lineinfo.count {
                            retval.currentLine = Int(cl.proto.lineinfo[savedpc == 0 ? 0 : savedpc-1])
                        } else {
                            retval.currentLine = -1
                        }
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
                retval.isTailCall = await ci.tailcalls > 0
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

    public func info(at level: Int, with options: Lua.Debug.InfoFlags = .all) async -> Lua.Debug? {
        if level < 0 || level >= callStack.count {
            return nil
        }
        let ci = callStack[callStack.count - level - 1]
        let previous = level == callStack.count - 1 ? nil : callStack[callStack.count - level - 2]
        return await info(with: options, in: ci, previous: previous, for: await ci.function, at: level)
    }

    public func info(for function: LuaFunction, with options: Lua.Debug.InfoFlags = .all) async -> Lua.Debug {
        return await info(with: options, in: nil, previous: nil, for: function, at: nil)
    }

    public func local(at level: Int, index: Int) async throws -> (String, LuaValue)? {
        if level < 0 || level >= callStack.count {
            throw Lua.LuaError.runtimeError(message: "bad argument (level out of range)")
        }
        return try await callStack[callStack.count - level - 1].local(index)
    }

    public func local(at level: Int, index: Int, value: LuaValue) async throws -> String? {
        if level < 0 || level >= callStack.count {
            throw Lua.LuaError.runtimeError(message: "bad argument (level out of range)")
        }
        return try await callStack[callStack.count - level - 1].local(index, value: value)
    }

    public func hook() -> (LuaFunction, Lua.HookFlags, Int)? {
        if let hook = hookFunction {
            return (hook, hookFlags, hookCount)
        }
        return nil
    }

    public func hook(function: LuaFunction?, for events: Lua.HookFlags, count: Int = 0) {
        if let hook = function, !events.isEmpty {
            hookFunction = hook
            hookFlags = events
            hookCount = count
        } else {
            hookFunction = nil
            hookFlags = []
            hookCount = 0
        }
    }

    public func call(closure cl: LuaClosure, with args: [LuaValue]) async throws -> [LuaValue] {
        let top = callStack.count
        do {
            return try await LuaVM.execute(closure: cl, with: args, numResults: nil, state: self)
        } catch LuaThread.CoroutineError.cancel {
            throw LuaThread.CoroutineError.cancel
        } catch let error {
            callStack.removeLast(callStack.count - top)
            throw error
        }
    }

    public func pcall(closure cl: LuaClosure, with args: [LuaValue], handler: (Error) async throws -> LuaValue) async throws -> [LuaValue] {
        let top = callStack.count
        do {
            return try await LuaVM.execute(closure: cl, with: args, numResults: nil, state: self)
        } catch LuaThread.CoroutineError.cancel {
            throw LuaThread.CoroutineError.cancel
        } catch let error {
            defer {callStack.removeLast(callStack.count - top)}
            do {
                let value = try await handler(error)
                throw Lua.LuaError.luaError(message: value)
            } catch LuaThread.CoroutineError.cancel {
                throw LuaThread.CoroutineError.cancel
            } catch {
                throw await self.error(message: "error in error handling")
            }
        }
    }

    internal func pushDummy(_ ci: CallInfo) {
        callStack.append(ci)
    }

    internal func popStack() {
        _ = callStack.popLast()
    }

    internal func stackIsEmpty() -> Bool {
        return callStack.isEmpty
    }

    internal func top() -> CallInfo {
        return callStack.last!
    }

    internal func processHooks(at pc: Int, in cl: LuaClosure, savedpc: Int) async throws {
        try await luaState.finalizeTables(in: self)
        if hookCount > 0 {
            hookCountLeft -= 1
        }
        if let hook = hookFunction, allowHooks {
            if hookFlags.contains(.count) && hookCount > 0 && hookCountLeft == 0 {
                allowHooks = false
                defer {allowHooks = true}
                _ = try await hook.call(in: self, with: [.string(.string("count"))])
                hookCountLeft = hookCount
            }
            if hookFlags.contains(.line) && (pc == 0 || (pc < cl.proto.lineinfo.count && cl.proto.lineinfo[savedpc] != cl.proto.lineinfo[pc])) {
                allowHooks = false
                defer {allowHooks = true}
                _ = try await hook.call(in: self, with: [.string(.string("line")), .number(Double(cl.proto.lineinfo[pc]))])
            }
        }
    }

    internal func processHooksForReturn() async throws {
        if let hook = hookFunction, allowHooks && hookFlags.contains(.return) {
            allowHooks = false
            defer {allowHooks = true}
            _ = try await hook.call(in: self, with: [.string(.string("return"))])
        }
    }

    internal func prepareCall(for ci: CallInfo) async throws {
        callStack.append(ci)
        if let hook = hookFunction, hookFlags.contains(.call) {
            _ = try await hook.call(in: self, with: [.string(.string("call"))])
        }
    }

    internal func prepareCall(for ci: CallInfo, tailCall: Bool) async throws {
        callStack.append(ci)
        if let hook = hookFunction, allowHooks && hookFlags.contains(tailCall ? .tailCall : .call) {
            allowHooks = false
            defer {allowHooks = true}
            _ = try await hook.call(in: self, with: [.string(.string(tailCall ? "tail call" : "call"))])
        }
    }

    internal func call(swift sfn: LuaSwiftFunction, function fn: LuaFunction, in ci: CallInfo, at idx: Int, args: Int?, returns: Int?, tailCall: Bool) async throws -> [LuaValue] {
        callStack.append(CallInfo(for: fn, numResults: returns, stackSize: 0))
        let argv = await ci.get(args: args, at: idx)
        //print("Arguments:", argv)
        if let hook = hookFunction, allowHooks && hookFlags.contains(tailCall ? .tailCall : .call) {
            allowHooks = false
            defer {allowHooks = true}
            _ = try await hook.call(in: self, with: [.string(.string(tailCall ? "tail call" : "call"))])
        }
        let L = Lua(in: self)
        let res = try await sfn.body(L, LuaArgs(argv, state: L))
        if !tailCall, let hook = hookFunction, allowHooks && hookFlags.contains(.return) {
            allowHooks = false
            defer {allowHooks = true}
            _ = try await hook.call(in: self, with: [.string(.string("return"))])
        }
        return res
    }
}