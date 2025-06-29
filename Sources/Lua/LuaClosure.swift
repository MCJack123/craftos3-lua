public actor LuaClosure: Hashable, Sendable, AsyncHashable {
    public var upvalues: [LuaUpvalue]
    public let proto: LuaInterpretedFunction

    private init(for fn: LuaInterpretedFunction, with upval: [LuaUpvalue]) {
        proto = fn
        upvalues = upval
    }

    internal static func create(for fn: LuaInterpretedFunction, with upval: [LuaUpvalue]) -> LuaClosure {
        return LuaClosure(for: fn, with: upval)
    }

    public func upvalue(_ index: Int) -> LuaUpvalue? {
        if index > 0 && index <= upvalues.count {
            return upvalues[index-1]
        }
        return nil
    }

    public func upvalue(_ index: Int, value: LuaUpvalue) throws {
        if index > 0 && index <= upvalues.count {
            upvalues[index-1] = value
        } else {
            throw Lua.LuaError.internalError
        }
    }

    public static func == (lhs: LuaClosure, rhs: LuaClosure) -> Bool {
        return lhs === rhs
    }

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(Unmanaged.passUnretained(self).toOpaque())
    }

    internal func equals(_ proto: LuaInterpretedFunction, _ upvalues: [LuaUpvalue]) -> Bool {
        return self.proto == proto && self.upvalues == upvalues
    }

    public func equals(otherAsync cl: LuaClosure) async -> Bool {
        return await cl.equals(proto, upvalues)
    }

    public func hash(intoAsync hasher: inout Hasher) async {
        hasher.combine(proto)
        for upval in upvalues {
            hasher.combine(Unmanaged.passUnretained(upval).toOpaque())
        }
    }
}