public enum LuaFunction: Hashable {
    case lua(LuaClosure)
    case swift(LuaSwiftFunction)

    public func call(in state: LuaThread, with args: [LuaValue]) async throws -> [LuaValue] {
        switch self {
            case .lua(let cl):
                let top = state.callStack.count
                do {
                    return try await LuaVM.execute(closure: cl, with: args, numResults: 0, state: state)
                } catch let error {
                    state.callStack.removeLast(state.callStack.count - top)
                    throw error
                }
            case .swift(let fn):
                return try await fn.body(Lua(in: state), LuaArgs(args))
        }
    }

    public func call(in state: LuaThread, with args: LuaArgs) async throws -> [LuaValue] {
        return try await call(in: state, with: args.args)
    }
}