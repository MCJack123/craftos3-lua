public enum LuaFunction: Hashable, Sendable {
    case lua(LuaClosure)
    case swift(LuaSwiftFunction)

    public func call(in state: LuaThread, with args: [LuaValue]) async throws -> [LuaValue] {
        switch self {
            case .lua(let cl):
                return try await state.call(closure: cl, with: args)
            case .swift(let fn):
                let L = Lua(in: state)
                return try await fn.body(L, LuaArgs(args, state: L))
        }
    }

    public func call(in state: LuaThread, with args: LuaArgs) async throws -> [LuaValue] {
        return try await call(in: state, with: args.args)
    }

    public func pcall(in state: LuaThread, with args: [LuaValue], handler: @Sendable (Error) async throws -> LuaValue) async throws -> [LuaValue] {
        switch self {
            case .lua(let cl):
                return try await state.pcall(closure: cl, with: args, handler: handler)
            case .swift(let fn):
                let L = Lua(in: state)
                return try await fn.body(L, LuaArgs(args, state: L))
        }
    }

    public func pcall(in state: LuaThread, with args: LuaArgs, handler: @Sendable (Error) async throws -> LuaValue) async throws -> [LuaValue] {
        return try await pcall(in: state, with: args.args, handler: handler)
    }
}