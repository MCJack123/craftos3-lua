public class LuaState {
    public var nilMetatable: LuaTable? = nil
    public var booleanMetatable: LuaTable? = nil
    public var numberMetatable: LuaTable? = nil
    public var stringMetatable: LuaTable? = nil
    public var functionMetatable: LuaTable? = nil
    public var threadMetatable: LuaTable? = nil
    public var currentThread: LuaThread!

    public init() {
        currentThread = LuaThread(in: self)
    }
}