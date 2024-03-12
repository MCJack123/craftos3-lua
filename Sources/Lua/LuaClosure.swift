public class LuaClosure: Hashable {
    public var upvalues: [LuaUpvalue]
    public let proto: LuaInterpretedFunction

    public init(for fn: LuaInterpretedFunction, with upval: [LuaUpvalue]) {
        proto = fn
        upvalues = upval
    }

    public static func == (lhs: LuaClosure, rhs: LuaClosure) -> Bool {
        return lhs.proto == rhs.proto && lhs.upvalues == rhs.upvalues
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(Unmanaged.passUnretained(self).toOpaque())
    }
}