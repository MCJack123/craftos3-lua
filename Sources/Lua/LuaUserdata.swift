public class LuaUserdata: Hashable {
    public let object: AnyObject
    public var metatable: LuaTable? = nil

    public init(for obj: AnyObject) {
        self.object = obj
    }

    public static func == (lhs: LuaUserdata, rhs: LuaUserdata) -> Bool {
        return lhs.object === rhs.object && lhs.metatable === rhs.metatable
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(Unmanaged.passUnretained(object).toOpaque())
        hasher.combine(metatable)
    }
}