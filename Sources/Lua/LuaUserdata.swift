public class LuaUserdata: Hashable {
    public let object: AnyObject
    public var metatable: LuaTable? = nil

    public init(for obj: AnyObject, with mt: LuaTable? = nil) {
        self.object = obj
        self.metatable = mt
    }

    public static func == (lhs: LuaUserdata, rhs: LuaUserdata) -> Bool {
        return lhs.object === rhs.object && lhs.metatable === rhs.metatable
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(Unmanaged.passUnretained(object).toOpaque())
        hasher.combine(metatable)
    }
}