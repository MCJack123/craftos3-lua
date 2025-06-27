public final class LuaSwiftFunction: Hashable, Sendable {
    internal let body: @Sendable (Lua, LuaArgs) async throws -> [LuaValue]

    public init(from fn: @escaping @Sendable (Lua, LuaArgs) async throws -> [LuaValue]) {
        body = fn
    }

    public static let empty = LuaSwiftFunction {_, _ in []}

    public static func == (lhs: LuaSwiftFunction, rhs: LuaSwiftFunction) -> Bool {
        return lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(Unmanaged.passUnretained(self).toOpaque())
    }
}