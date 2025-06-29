public protocol LuaUserdata: Hashable, Sendable, Equatable {
    var object: any Sendable & AnyObject {get}
    var metatable: LuaTable? {get async}
    var uservalue: LuaValue {get async}
    func set(metatable: LuaTable?) async
    func set(uservalue: LuaValue) async
}

public actor LuaFullUserdata: LuaUserdata {
    public let object: any Sendable & AnyObject
    public var metatable: LuaTable? = nil
    public var uservalue: LuaValue = .nil

    public init(for obj: any Sendable & AnyObject, with mt: LuaTable? = nil) {
        self.object = obj
        self.metatable = mt
    }

    public static func == (lhs: LuaFullUserdata, rhs: LuaFullUserdata) -> Bool {
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

public struct LuaLightUserdata: LuaUserdata {
    public let object: any Sendable & AnyObject
    public var metatable: LuaTable? {return nil}
    public var uservalue: LuaValue {return .nil}

    public init(for obj: any Sendable & AnyObject) {
        self.object = obj
    }

    public static func == (lhs: LuaLightUserdata, rhs: LuaLightUserdata) -> Bool {
        return lhs.object === rhs.object
    }

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(Unmanaged.passUnretained(object).toOpaque())
    }

    public func set(metatable: LuaTable?) {
        // do nothing
    }

    public func set(uservalue: LuaValue) {
        // do nothing
    }
}
