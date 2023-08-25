public class LuaSwiftFunction: Hashable {
    internal let body: (Lua, [LuaValue]) async throws -> [LuaValue]

    public init(from fn: @escaping (Lua, [LuaValue]) async throws -> [LuaValue]) {
        body = fn
    }

    public static func == (lhs: LuaSwiftFunction, rhs: LuaSwiftFunction) -> Bool {
        return lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(Unmanaged.passUnretained(self).toOpaque())
    }
}