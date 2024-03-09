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
}