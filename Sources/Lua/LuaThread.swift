public class LuaThread: Hashable {
    public static func == (lhs: LuaThread, rhs: LuaThread) -> Bool {
        return lhs.task == rhs.task
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(task)
    }

    /// The current state of the coroutine.
    public enum State {
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
        if state.currentThread == nil {
            throw CoroutineError.noCoroutine
        }
        if state.currentThread.state != .running {
            throw CoroutineError.noCoroutine
        }
        unowned let coro = state.currentThread
        coro!.state = .suspended
        return try await withCheckedThrowingContinuation {continuation in
            let c = coro!.continuation!
            coro!.continuation = continuation
            c.resume(returning: args)
        }
    }

    public static func yield(in state: Lua, with args: [LuaValue] = [LuaValue]()) async throws -> [LuaValue] {
        return try await yield(in: state.thread.luaState, with: args)
    }

    private var task: Task<Void, Error>!
    private var continuation: CheckedContinuation<[LuaValue], Error>!
    internal var callStack = [CallInfo]()
    internal var luaState: LuaState
    internal var hookFunction: LuaFunction?
    internal var hookFlags: Lua.HookFlags = []
    internal var hookCount: Int = 0
    internal var hookCountLeft: Int = 0
    internal var allowHooks = true
    
    /// The current state of the coroutine.
    public private(set) var state: State = .suspended

    /// Creates a new coroutine around a Lua function.
    /// 
    /// - Parameter body: The main function of the coroutine.
    public init(in L: LuaState, for body: LuaFunction) async {
        luaState = L
        task = Task {[weak self] in
            let args = try await withCheckedThrowingContinuation {continuation in
                self!.continuation = continuation
            }
            do {
                let res = try await body.call(in: self!, with: args)
                self?.state = .dead
                self?.continuation.resume(returning: res)
            } catch {
                self?.state = .dead
                self?.continuation.resume(throwing: error)
            }
        }
        while continuation == nil {await Task.yield()}
    }

    convenience public init(in L: Lua, for body: LuaFunction) async {
        await self.init(in: L.thread.luaState, for: body)
    }

    /// Creates a new coroutine around a closure which takes no arguments and returns no values.
    /// 
    /// - Parameter body: The main function of the coroutine.
    public init(in L: LuaState, for body: @escaping () async throws -> ()) async {
        luaState = L
        task = Task {[weak self] in
            _ = try await withCheckedThrowingContinuation {continuation in
                self!.continuation = continuation
            }
            do {
                try await body()
                self?.state = .dead
                self?.continuation.resume(returning: [])
            } catch {
                self?.state = .dead
                self?.continuation.resume(throwing: error)
            }
        }
        while continuation == nil {await Task.yield()}
    }

    convenience public init(in L: Lua, for body: @escaping () async throws -> ()) async {
        await self.init(in: L.thread.luaState, for: body)
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
        let old = state.currentThread
        old?.state = .normal
        state.currentThread = self
        let res = try await withCheckedThrowingContinuation {nextContinuation in
            let c = continuation!
            continuation = nextContinuation
            c.resume(returning: args)
        }
        state.currentThread = old
        old?.state = .running
        return res
    }

    public func resume(in state: Lua, with args: [LuaValue] = [LuaValue]()) async throws -> [LuaValue] {
        return try await resume(in: state.thread.luaState, with: args)
    }
}