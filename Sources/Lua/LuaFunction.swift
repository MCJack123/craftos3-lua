public enum LuaFunction: Hashable {
    case lua(LuaClosure)
    case swift(LuaSwiftFunction)

    public func call(in state: LuaThread, with args: [LuaValue]) async throws -> [LuaValue] {
        switch self {
            case .lua(let cl):
                return try await LuaVM.execute(closure: cl, with: args, numResults: 0, state: state)
            case .swift(let fn):
                return try await fn.body(Lua(in: state), args)
        }
    }
}