public actor LuaUserdata: Hashable {
    public let object: any Sendable
    public var metatable: LuaTable? = nil
    public var uservalue: LuaValue = .nil

    public init(for obj: any Sendable, with mt: LuaTable? = nil) {
        self.object = obj
        self.metatable = mt
    }

    public static func == (lhs: LuaUserdata, rhs: LuaUserdata) -> Bool {
        return lhs === rhs
    }

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(Unmanaged.passUnretained(self).toOpaque())
    }

    public func set(metatable: LuaTable?) {
        self.metatable = metatable
    }

    public func set(uservalue: LuaValue) {
        self.uservalue = uservalue
    }
}