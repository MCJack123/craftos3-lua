public enum LuaFunction: Hashable {
    case lua(LuaClosure)
    case swift(LuaSwiftFunction)

    public func call(in state: LuaThread, with args: [LuaValue]) async throws -> [LuaValue] {
        switch self {
            case .lua(let cl):
                let top = state.callStack.count
                do {
                    return try await LuaVM.execute(closure: cl, with: args, numResults: nil, state: state)
                } catch let error {
                    state.callStack.removeLast(state.callStack.count - top)
                    throw error
                }
            case .swift(let fn):
                let L = Lua(in: state)
                return try await fn.body(L, LuaArgs(args, state: L))
        }
    }

    public func call(in state: LuaThread, with args: LuaArgs) async throws -> [LuaValue] {
        return try await call(in: state, with: args.args)
    }

    public func pcall(in state: LuaThread, with args: [LuaValue], handler: (Error) async throws -> LuaValue) async throws -> [LuaValue] {
        switch self {
            case .lua(let cl):
                let top = state.callStack.count
                do {
                    return try await LuaVM.execute(closure: cl, with: args, numResults: nil, state: state)
                } catch LuaThread.CoroutineError.cancel {
                    throw LuaThread.CoroutineError.cancel
                } catch let error {
                    defer {state.callStack.removeLast(state.callStack.count - top)}
                    do {
                        let value = try await handler(error)
                        throw Lua.LuaError.luaError(message: value)
                    } catch LuaThread.CoroutineError.cancel {
                        throw LuaThread.CoroutineError.cancel
                    } catch {
                        throw Lua.error(in: state, message: "error in error handling")
                    }
                }
            case .swift(let fn):
                let L = Lua(in: state)
                return try await fn.body(L, LuaArgs(args, state: L))
        }
    }

    public func pcall(in state: LuaThread, with args: LuaArgs, handler: (Error) async throws -> LuaValue) async throws -> [LuaValue] {
        return try await pcall(in: state, with: args.args, handler: handler)
    }
}