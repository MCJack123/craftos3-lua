public class LuaClosure: Hashable {
    public let upvalues: [LuaUpvalue]
    public let proto: LuaInterpretedFunction
    public var environment: LuaTable

    public init(for fn: LuaInterpretedFunction, with upval: [LuaUpvalue], environment env: LuaTable) {
        proto = fn
        upvalues = upval
        environment = env
    }

    public static func == (lhs: LuaClosure, rhs: LuaClosure) -> Bool {
        return lhs === rhs
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(Unmanaged.passUnretained(self).toOpaque())
    }
}